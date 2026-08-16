"""Pure-numpy generative check of the weight regression (no .mat needed)."""

import numpy as np

from slice_ephys_analysis import regression


def make_problem(n_trials=300, n_cells=25, noise=0.5, seed=0):
    rng = np.random.default_rng(seed)
    w_true = np.zeros(n_cells)
    connected = rng.choice(n_cells, size=8, replace=False)
    w_true[connected] = rng.lognormal(0.5, 0.4, size=8)
    X = np.zeros((n_trials, n_cells))
    for i in range(n_trials):
        members = rng.choice(n_cells, size=rng.integers(5, 12), replace=False)
        X[i, members] = rng.choice([0.25, 0.5, 0.75, 1.0], size=members.size)
    y = X @ w_true + noise * rng.standard_normal(n_trials)
    return X, y, w_true


def test_ridge_recovers_weights():
    X, y, w_true = make_problem()
    fit = regression.fit_weights(X, y, model="ridge")
    r = np.corrcoef(fit["w"], w_true)[0, 1]
    assert r > 0.95
    assert fit["cv_r2"] > 0.7


def test_lasso_recovers_sparsity():
    X, y, w_true = make_problem(noise=0.3)
    fit = regression.fit_weights(X, y, model="lasso")
    zero_true = w_true == 0
    # Most true zeros stay (near) zero under lasso.
    assert np.mean(np.abs(fit["w"][zero_true]) < 0.1) > 0.8


def test_permutation_null_separates_connected():
    X, y, w_true = make_problem(noise=0.3)
    fit = regression.fit_weights(X, y, model="ridge", n_permutations=50)
    connected = w_true > 0
    # Connected cells exceed the null band; unconnected mostly stay inside.
    assert np.mean(fit["w"][connected] > fit["null_hi"][connected]) > 0.7
    assert np.mean(np.abs(fit["w"][~connected]) <= fit["null_hi"][~connected]) > 0.7


def test_shape_mismatch_raises():
    X, y, _ = make_problem()
    try:
        regression.fit_weights(X, y[:-1])
        raise AssertionError("expected ValueError")
    except ValueError:
        pass
