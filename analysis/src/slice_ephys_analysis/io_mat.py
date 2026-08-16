"""Read MATLAB v7.3 (.mat = HDF5) files written by the sem MATLAB package.

Only the subset of MATLAB types sem actually writes is supported: numeric
arrays, logicals, char arrays, structs (arbitrarily nested), and cell arrays
of those. MATLAB classes that save as opaque blobs (datetime, string) are
returned as None — the sem data schema deliberately avoids putting anything
Python needs into such fields (see docs/DATA_SCHEMA.md).

MATLAB stores arrays column-major; h5py exposes them transposed. Every array
is transposed back here, and 1xN / Nx1 arrays squeeze to 1-D. Scalars come
back as Python floats.
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import h5py
import numpy as np


def _decode_char(arr: np.ndarray) -> str:
    """MATLAB char arrays save as uint16 code units, column-major."""
    a = np.atleast_2d(arr)
    # (rows, cols) after our transpose; MATLAB chars are row vectors in practice.
    return "".join(chr(int(c)) for c in a.flatten() if int(c) != 0)


def _read_item(f: h5py.File, obj: Any) -> Any:
    if isinstance(obj, h5py.Group):
        cls = obj.attrs.get("MATLAB_class", b"").decode() if "MATLAB_class" in obj.attrs else ""
        if cls in ("datetime", "string", "table", "categorical"):
            return None  # opaque MATLAB classes: schema keeps these Python-irrelevant
        out = {}
        for k in obj.keys():
            if k.startswith("#"):
                continue
            try:
                out[k] = _read_item(f, obj[k])
            except Exception:
                out[k] = None
        return out

    if not isinstance(obj, h5py.Dataset):
        return None

    if "MATLAB_empty" in obj.attrs and int(np.array(obj.attrs["MATLAB_empty"])) == 1:
        return np.empty((0,))

    cls = obj.attrs.get("MATLAB_class", b"").decode() if "MATLAB_class" in obj.attrs else ""
    data = obj[()]

    if isinstance(data, np.ndarray) and data.dtype == h5py.ref_dtype:
        # Cell array: array of object references, column-major.
        refs = data.T.flatten()
        return [_read_item(f, f[r]) for r in refs]

    if cls == "char":
        return _decode_char(np.asarray(data).T)

    if isinstance(data, np.ndarray):
        arr = data.T
        if cls == "logical":
            arr = arr.astype(bool)
        if arr.size == 1:
            return float(arr.flatten()[0])
        if 1 in arr.shape or arr.ndim == 1:
            return arr.flatten()
        return arr

    if np.isscalar(data):
        return float(data)
    return data


def load_mat(path: str | Path) -> dict[str, Any]:
    """Load every top-level variable of a v7.3 .mat file into a dict."""
    out: dict[str, Any] = {}
    with h5py.File(path, "r") as f:
        for k in f.keys():
            if k.startswith("#"):
                continue
            out[k] = _read_item(f, f[k])
    return out


# ---------------------------------------------------------------------------
# Session-level loaders (the sem on-disk schema; see docs/DATA_SCHEMA.md)
# ---------------------------------------------------------------------------

def load_ensembles(session_dir: str | Path) -> dict:
    """ensembles.mat -> dict with X (nTrials x nCells), cellIds, kinds, ..."""
    ens = load_mat(Path(session_dir) / "ensembles.mat")["ens"]
    ens["X"] = np.atleast_2d(np.asarray(ens["X"], dtype=float))
    ens["cellIds"] = np.asarray(ens["cellIds"], dtype=float).flatten()
    if ens["X"].shape[1] != ens["cellIds"].size:
        ens["X"] = ens["X"].T  # 1-row edge cases
    ens["kinds"] = [k if isinstance(k, str) else "" for k in ens["kinds"]]
    return ens


def load_ground_truth(session_dir: str | Path) -> dict | None:
    p = Path(session_dir) / "ground_truth.mat"
    if not p.exists():
        return None
    gt = load_mat(p)["gt"]
    for key in ("W_E_eff", "W_I_eff", "opsinGain", "cellIds", "W_E_pC", "cI"):
        if key in gt and gt[key] is not None:
            gt[key] = np.asarray(gt[key], dtype=float).flatten()
    return gt


def load_targets(session_dir: str | Path) -> dict:
    return load_mat(Path(session_dir) / "targets.mat")["targets"]


class Trial:
    """One trial joined from its meta (+ optional raw) file."""

    def __init__(self, meta: dict, raw: dict | None):
        self.meta = meta
        self.raw = raw

    @property
    def status(self) -> str:
        return self.meta.get("status", "")

    @property
    def ephys(self) -> dict:
        return self.meta.get("metadata", {}).get("ephys", {})

    @property
    def kind(self) -> str:
        return self.ephys.get("kind", "")

    @property
    def ensemble_id(self) -> float:
        return self.ephys.get("ensembleId", float("nan"))

    @property
    def fs(self) -> float:
        return float(self.meta.get("daq_master_sample_rate_hz", float("nan")))

    @property
    def onset_in_snippet(self) -> int:
        return int(self.ephys.get("stimOnsetSampleInSnippet", 0))

    def ai(self) -> np.ndarray | None:
        """Raw AI snippet (nSamples x nAI), DAQ volts."""
        if self.raw is None:
            return None
        ai = self.raw.get("aiData")
        if ai is None or np.asarray(ai).size == 0:
            return None
        return np.atleast_2d(np.asarray(ai, dtype=float))

    def scaled_output_volts(self) -> np.ndarray | None:
        """The Multiclamp scaled-output column of the snippet, DAQ volts."""
        ai = self.ai()
        if ai is None:
            return None
        col = int(self.ephys["aiChannelMap"]["scaledOutput"]) - 1  # MATLAB 1-based
        if ai.shape[1] <= col:
            ai = ai.T  # 1-channel snippets flatten; ensure samples along axis 0
        if ai.ndim == 1 or ai.shape[1] <= col:
            return ai.flatten()
        return ai[:, col]


class Block:
    """One clamp block: label, holding, and its trials."""

    def __init__(self, block_dir: Path):
        self.block_dir = block_dir
        self.trials: list[Trial] = []
        for meta_path in sorted(block_dir.glob("trials/*_meta.mat")):
            meta = load_mat(meta_path)["meta"]
            raw_path = Path(str(meta_path).replace("_meta.mat", "_raw.mat"))
            raw = load_mat(raw_path)["raw"] if raw_path.exists() else None
            self.trials.append(Trial(meta, raw))

    @property
    def label(self) -> str:
        for t in self.trials:
            lbl = t.ephys.get("blockLabel")
            if lbl:
                return lbl
        return ""

    @property
    def holding_mv(self) -> float:
        for t in self.trials:
            if t.kind != "sealTest":
                return float(t.ephys.get("holdingMv", float("nan")))
        return float("nan")

    @property
    def clamp_mode(self) -> str:
        for t in self.trials:
            if t.kind != "sealTest":
                return t.ephys.get("clampMode", "")
        return ""

    def stim_trials(self) -> list[Trial]:
        return [t for t in self.trials
                if t.status == "complete" and t.kind in ("ensemble", "single", "direct")]

    def blank_trials(self) -> list[Trial]:
        return [t for t in self.trials if t.status == "complete" and t.kind == "blank"]


class SessionIndex:
    """A whole session directory: ensembles + ground truth + blocks."""

    def __init__(self, session_dir: str | Path):
        self.session_dir = Path(session_dir)
        self.ensembles = load_ensembles(self.session_dir)
        self.ground_truth = load_ground_truth(self.session_dir)
        self.blocks: list[Block] = []
        for block_dir in sorted(self.session_dir.glob("block_*")):
            if block_dir.is_dir():
                self.blocks.append(Block(block_dir))
        if not self.blocks:
            # Blocks may live one level down (blocks/ subdir variant).
            for block_dir in sorted(self.session_dir.glob("*/block_*")):
                if block_dir.is_dir():
                    self.blocks.append(Block(block_dir))

    def block_by_holding(self, holding_mv: float) -> Block | None:
        for b in self.blocks:
            if np.isfinite(b.holding_mv) and abs(b.holding_mv - holding_mv) < 1e-6:
                return b
        return None

    def block_by_label(self, label: str) -> Block | None:
        pattern = re.sub(r"[^A-Za-z0-9]", "", label).lower()
        for b in self.blocks:
            if re.sub(r"[^A-Za-z0-9]", "", b.label).lower() == pattern:
                return b
        return None
