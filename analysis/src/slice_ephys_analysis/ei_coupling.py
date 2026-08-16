"""E/I coupling across ensembles — the biological question of the project.

Every ensemble was presented at both -70 mV (E) and +10 mV (I), so evoked E
and I charges pair by ensembleId. This module quantifies how tightly the
inhibition recruited by an ensemble tracks its excitation, and finds the
outliers (high-E/low-I and vice versa) that would indicate non-uniformly
coupled subnetworks.
"""

from __future__ import annotations

import numpy as np


def pair_by_ensemble(design_e: dict, design_i: dict) -> dict:
    """Match E-block and I-block designs on ensembleId.

    Inputs are design.block_design outputs (rep-averaged or not). Returns
    dict with ensemble_ids, e (pC, positive = more excitation), i (pC,
    positive = more inhibition), X (fill design rows for the paired set).
    """
    ids_e = design_e["ensemble_ids"]
    ids_i = design_i["ensemble_ids"]
    common, idx_e, idx_i = np.intersect1d(ids_e, ids_i, return_indices=True)
    return {
        "ensemble_ids": common,
        "e": design_e["y"][idx_e],
        "i": design_i["y"][idx_i],
        "X": design_e["X"][idx_e, :],
    }


def coupling_stats(paired: dict) -> dict:
    """Correlation + linear I~E fit + studentized residual outliers."""
    e, i = paired["e"], paired["i"]
    if e.size < 3:
        raise ValueError("need at least 3 paired ensembles")
    r = float(np.corrcoef(e, i)[0, 1])
    slope, intercept = np.polyfit(e, i, 1)
    resid = i - (slope * e + intercept)
    sd = float(np.std(resid))
    z = resid / sd if sd > 0 else np.zeros_like(resid)
    return {
        "r": r,
        "slope": float(slope),
        "intercept": float(intercept),
        "residual_z": z,
        "high_e_low_i": paired["ensemble_ids"][z < -2.0],
        "low_e_high_i": paired["ensemble_ids"][z > 2.0],
    }


def per_cell_ei_weights(fit_e: dict, fit_i: dict) -> dict:
    """Compare per-cell W_E vs W_I from the two block regressions."""
    w_e, w_i = fit_e["w"], fit_i["w"]
    ok = np.isfinite(w_e) & np.isfinite(w_i)
    r = float(np.corrcoef(w_e[ok], w_i[ok])[0, 1]) if ok.sum() > 2 else float("nan")
    return {"w_e": w_e, "w_i": w_i, "r": r}
