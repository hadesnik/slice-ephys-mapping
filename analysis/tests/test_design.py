"""design.block_design on stubbed trials: sign conventions + ensembleId join."""

import numpy as np

from slice_ephys_analysis import design

FS = 20000.0
GAIN = {"commandVcMvPerV": 20, "commandIcPaPerV": 400,
        "scaledVcPaPerV": 1000, "scaledIcMvPerMv": 20}


class StubTrial:
    def __init__(self, ensemble_id, charge_pc, kind="ensemble", holding=-70.0):
        self.status = "complete"
        self.kind = kind
        self.ensemble_id = float(ensemble_id)
        self.fs = FS
        self.onset_in_snippet = 1000
        self.ephys = {"gains": GAIN, "holdingMv": holding,
                      "aiChannelMap": {"scaledOutput": 1}}
        self._charge = charge_pc

    def scaled_output_volts(self):
        n = 6000
        t = np.arange(n) / FS
        tau_r, tau_d = 0.0005, 0.003
        k = np.zeros(n)
        tt = t - self.onset_in_snippet / FS - 0.003
        valid = tt >= 0
        k[valid] = np.exp(-tt[valid] / tau_d) - np.exp(-tt[valid] / tau_r)
        k /= (tau_d - tau_r)
        trace_pa = self._charge * k
        return trace_pa / GAIN["scaledVcPaPerV"]  # back to DAQ volts


class StubBlock:
    def __init__(self, trials, holding):
        self._trials = trials
        self.holding_mv = holding

    def stim_trials(self):
        return [t for t in self._trials if t.kind in ("ensemble", "single", "direct")]

    def blank_trials(self):
        return [t for t in self._trials if t.kind == "blank"]


def make_ens(n_trials=4, n_cells=3):
    rng = np.random.default_rng(1)
    return {"X": rng.uniform(0, 1, (n_trials, n_cells)),
            "cellIds": np.arange(1, n_cells + 1, dtype=float)}


def test_e_block_flips_inward_positive():
    ens = make_ens()
    trials = [StubTrial(1, -3.0), StubTrial(2, -1.5)]
    d = design.block_design(StubBlock(trials, -70.0), ens)
    assert np.allclose(d["y"], [3.0, 1.5], rtol=0.05)
    assert list(d["ensemble_ids"]) == [1, 2]


def test_i_block_keeps_outward_positive():
    ens = make_ens()
    trials = [StubTrial(3, +2.0, holding=10.0)]
    d = design.block_design(StubBlock(trials, 10.0), ens)
    assert np.allclose(d["y"], [2.0], rtol=0.05)


def test_x_rows_follow_ensemble_ids():
    ens = make_ens()
    trials = [StubTrial(4, -1.0), StubTrial(2, -1.0)]
    d = design.block_design(StubBlock(trials, -70.0), ens)
    assert np.allclose(d["X"][0], ens["X"][3])  # ensembleId 4 -> row index 3
    assert np.allclose(d["X"][1], ens["X"][1])


def test_blank_sigma_from_blanks():
    ens = make_ens()
    trials = [StubTrial(1, -3.0),
              StubTrial(float("nan"), 0.02, kind="blank"),
              StubTrial(float("nan"), -0.03, kind="blank")]
    d = design.block_design(StubBlock(trials, -70.0), ens)
    assert np.isfinite(d["blank_sigma"])


def test_average_repeats():
    ens = make_ens()
    trials = [StubTrial(1, -2.0), StubTrial(1, -4.0), StubTrial(2, -1.0)]
    d = design.average_repeats(design.block_design(StubBlock(trials, -70.0), ens))
    assert d["y"].size == 2
    np.testing.assert_allclose(d["y"][0], 3.0, rtol=0.05)  # mean of 2.0 and 4.0
    np.testing.assert_allclose(d["y"][1], 1.0, rtol=0.05)
