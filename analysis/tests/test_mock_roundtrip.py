"""THE project exit test: recover known weights from a full mock session.

Run scripts/run_mock_session.m (MATLAB) first — it writes a seeded session
under data/. This test finds the newest data/mock_session_* directory (or
$SEM_MOCK_SESSION) and asserts the full-pipeline recovery thresholds:

  r(W_E_recovered, W_E_true) >= 0.9 on connected cells
  r(W_I_recovered, W_I_true) >= 0.8 (polysynaptic pathway, looser)
  opsin-/unconnected cells recover ~0 (under the permutation null)
  cross-validated R^2 above zero (the model explains held-out trials)

Skips with instructions when no mock session exists.
"""

import os
from pathlib import Path

import numpy as np
import pytest

from slice_ephys_analysis import validate


def find_session() -> Path | None:
    env = os.environ.get("SEM_MOCK_SESSION")
    if env:
        return Path(env)
    repo = Path(__file__).resolve().parents[2]
    candidates = sorted((repo / "data").glob("mock_session_*"))
    return candidates[-1] if candidates else None


session = find_session()
pytestmark = pytest.mark.skipif(
    session is None or not (session / "ground_truth.mat").exists(),
    reason="no mock session found — run scripts/run_mock_session.m in MATLAB first "
           "(or set $SEM_MOCK_SESSION)",
)


@pytest.fixture(scope="module")
def result():
    return validate.validate_session(session, model="ridge", n_permutations=50)


def test_e_weights_recovered(result):
    assert result["e"] is not None, "no VC-70 block in session"
    assert result["e"]["r_connected"] >= 0.9
    assert result["e"]["cv_r2"] > 0.0


def test_i_weights_recovered(result):
    assert result["i"] is not None, "no VC+10 block in session"
    assert result["i"]["r_connected"] >= 0.8


def test_zero_cells_stay_at_null(result):
    z = result["e"]["zero_cells_under_null"]
    if np.isfinite(z):
        assert z >= 0.7


def test_recovery_beats_noise_floor(result):
    e = result["e"]
    assert np.isfinite(e["blank_sigma"])
    # Mean recovered connected weight comfortably above the blank noise floor.
    w_true = e["w_true"]
    assert np.mean(e["w"][w_true > 0]) > 2 * e["blank_sigma"]
