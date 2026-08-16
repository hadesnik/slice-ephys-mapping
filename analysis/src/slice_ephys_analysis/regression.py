"""Per-cell weight estimation: ensemble design matrix -> patched-cell charge.

fit_weights solves y ~ X @ w with ridge (default) or lasso, cross-validated
over regularization strength. Weights have units pC per unit fill fraction —
the same quantity the mock's ground_truth.mat exports as W_E_eff / W_I_eff.

A permutation null (shuffle y, refit) gives a per-cell significance floor:
cells whose |w| stays inside the null band are "not detected" — the expected
outcome for opsin-negative and unconnected cells.
"""

from __future__ import annotations

import numpy as np
from sklearn.linear_model import LassoCV, RidgeCV
from sklearn.model_selection import KFold, cross_val_score


def fit_weights(X: np.ndarray, y: np.ndarray, model: str = "ridge",
                cv: int = 5, n_permutations: int = 0,
                random_state: int = 0) -> dict:
    """Fit w and CV metrics; optionally a permutation null band.

    Returns dict: w (nCells,), intercept, cv_r2, model, null_hi (per-cell
    97.5th percentile of |w| under shuffled y; NaN array if no permutations).
    """
    X = np.asarray(X, dtype=float)
    y = np.asarray(y, dtype=float)
    if X.shape[0] != y.size:
        raise ValueError(f"X has {X.shape[0]} rows but y has {y.size}")
    n_splits = min(cv, max(2, X.shape[0] // 2))

    def make_model():
        if model == "ridge":
            return RidgeCV(alphas=np.logspace(-3, 3, 13))
        if model == "lasso":
            return LassoCV(cv=n_splits, random_state=random_state, max_iter=50000)
        raise ValueError(f"unknown model {model!r}")

    est = make_model().fit(X, y)
    w = np.asarray(est.coef_, dtype=float).flatten()

    cv_r2 = float(np.mean(cross_val_score(
        make_model(), X, y, cv=KFold(n_splits, shuffle=True, random_state=random_state),
        scoring="r2")))

    null_hi = np.full(w.size, np.nan)
    if n_permutations > 0:
        rng = np.random.default_rng(random_state)
        null_w = np.zeros((n_permutations, w.size))
        for p in range(n_permutations):
            null_w[p] = np.asarray(make_model().fit(X, rng.permutation(y)).coef_).flatten()
        null_hi = np.percentile(np.abs(null_w), 97.5, axis=0)

    return {
        "w": w,
        "intercept": float(np.atleast_1d(est.intercept_)[0]),
        "cv_r2": cv_r2,
        "model": model,
        "null_hi": null_hi,
    }
