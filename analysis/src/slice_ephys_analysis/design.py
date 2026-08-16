"""Build the regression design (X, y) for one clamp block.

X comes from ensembles.mat — the design-matrix source of truth written by
sem.protocol.generateEnsembles — NEVER reconstructed from DMD patterns.
y is the per-trial evoked charge on the patched cell, sign-flipped so that
"more synaptic input" is positive for both E and I blocks:

  VC -70 block (E): evoked charge is inward/negative  -> y = -charge
  VC +10 block (I): evoked charge is outward/positive -> y = +charge

Trials are matched to design rows by ensembleId (the row index into ens.X),
which every trial carries in metadata.ephys — replay identity across blocks.
"""

from __future__ import annotations

import numpy as np

from . import psc, units
from .io_mat import Block


def block_design(block: Block, ens: dict,
                 window_s: tuple[float, float] = psc.TOTAL_WINDOW_S) -> dict:
    """Assemble X, y, and QC info for one block.

    Returns dict with:
      X            (nUsed x nCells) fill-fraction design rows
      y            (nUsed,) signed-corrected evoked charge (pC)
      ensemble_ids (nUsed,) 1-based rows into ens.X
      cell_ids     (nCells,)
      blank_sigma  noise floor: std of blank-trial "evoked charge"
      holding_mv, n_dropped
    """
    holding = block.holding_mv
    if not np.isfinite(holding):
        raise ValueError("block has no finite holdingMv (is this a CC block?)")
    sign = -1.0 if holding < -30 else 1.0  # -70 -> flip inward E positive

    X_full = np.asarray(ens["X"], dtype=float)
    rows, ys = [], []
    n_dropped = 0
    for t in block.stim_trials():
        v = t.scaled_output_volts()
        if v is None or not np.isfinite(t.ensemble_id):
            n_dropped += 1
            continue
        trace = units.scaled_daq_volts_to_cell(v, "VC", t.ephys["gains"])
        q = psc.evoked_charge(trace, t.fs, t.onset_in_snippet, window_s)
        if not np.isfinite(q):
            n_dropped += 1
            continue
        rows.append(int(t.ensemble_id) - 1)  # MATLAB 1-based -> 0-based
        ys.append(sign * q)

    blanks = []
    for t in block.blank_trials():
        v = t.scaled_output_volts()
        if v is None:
            continue
        trace = units.scaled_daq_volts_to_cell(v, "VC", t.ephys["gains"])
        q = psc.evoked_charge(trace, t.fs, t.onset_in_snippet, window_s)
        if np.isfinite(q):
            blanks.append(sign * q)

    return {
        "X": X_full[rows, :],
        "y": np.asarray(ys, dtype=float),
        "ensemble_ids": np.asarray(rows, dtype=int) + 1,
        "cell_ids": np.asarray(ens["cellIds"], dtype=float).flatten(),
        "blank_sigma": float(np.std(blanks)) if blanks else float("nan"),
        "holding_mv": holding,
        "n_dropped": n_dropped,
    }


def average_repeats(design: dict) -> dict:
    """Average y over repeated presentations of the same ensembleId."""
    ids = design["ensemble_ids"]
    uniq = np.unique(ids)
    X_out = np.zeros((uniq.size, design["X"].shape[1]))
    y_out = np.zeros(uniq.size)
    for i, u in enumerate(uniq):
        sel = ids == u
        X_out[i] = design["X"][np.argmax(sel)]
        y_out[i] = float(np.mean(design["y"][sel]))
    out = dict(design)
    out.update({"X": X_out, "y": y_out, "ensemble_ids": uniq})
    return out
