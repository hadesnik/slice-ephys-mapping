"""Mock-roundtrip validation: recovered weights vs ground_truth.mat.

The project's end-to-end truth test: scripts/run_mock_session.m synthesizes a
session from KNOWN weights; this module runs the full pipeline on it and
compares. test_mock_roundtrip.py asserts the thresholds.
"""

from __future__ import annotations

import numpy as np

from . import design, regression
from .io_mat import SessionIndex


def validate_session(session_dir, model: str = "ridge",
                     n_permutations: int = 0) -> dict:
    """Full pipeline on a mock session; returns recovery metrics.

    Returns dict with, per pathway (e / i): recovered w, true w, pearson r on
    connected cells, and (with permutations) the fraction of zero-truth cells
    that stay under the null band.
    """
    idx = SessionIndex(session_dir)
    if idx.ground_truth is None:
        raise FileNotFoundError(f"{session_dir} has no ground_truth.mat (not a mock session)")
    gt = idx.ground_truth

    out: dict = {"session_dir": str(session_dir)}
    for key, holding, w_true in (("e", -70.0, gt["W_E_eff"]),
                                 ("i", 10.0, gt["W_I_eff"])):
        block = idx.block_by_holding(holding)
        if block is None:
            out[key] = None
            continue
        d = design.average_repeats(design.block_design(block, idx.ensembles))
        fit = regression.fit_weights(d["X"], d["y"], model=model,
                                     n_permutations=n_permutations)
        w = fit["w"]
        # A cell that never appears in any ensemble (all-zero X column — the
        # patched cell is excluded from membership by design) has an
        # unmeasurable weight: leave it out of every recovery metric.
        measurable = np.any(np.asarray(d["X"]) > 0, axis=0)
        connected = (w_true > 1e-12) & measurable
        zero_truth = (w_true <= 1e-12) & measurable
        r = float(np.corrcoef(w[connected], w_true[connected])[0, 1]) \
            if connected.sum() > 2 else float("nan")
        zero_ok = float("nan")
        if n_permutations > 0 and zero_truth.any():
            zero_ok = float(np.mean(np.abs(w[zero_truth]) <= fit["null_hi"][zero_truth]))
        out[key] = {
            "w": w,
            "w_true": np.asarray(w_true, dtype=float),
            "r_connected": r,
            "cv_r2": fit["cv_r2"],
            "zero_cells_under_null": zero_ok,
            "n_trials": d["y"].size,
            "blank_sigma": d["blank_sigma"],
        }
    return out
