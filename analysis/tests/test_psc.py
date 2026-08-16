"""psc.evoked_charge must integrate a known synthetic PSC exactly."""

import numpy as np
import pytest

from slice_ephys_analysis import psc

FS = 20000.0


def make_trace(charge_pc: float, onset_idx: int = 1000, n: int = 6000,
               baseline_pa: float = -50.0) -> np.ndarray:
    """Difference-of-exponentials PSC with unit-normalized integral."""
    t = np.arange(n) / FS
    tau_r, tau_d = 0.0005, 0.003
    k = np.zeros(n)
    tt = t - onset_idx / FS - 0.003
    valid = tt >= 0
    k[valid] = np.exp(-tt[valid] / tau_d) - np.exp(-tt[valid] / tau_r)
    k /= (tau_d - tau_r)  # integral == 1
    return baseline_pa + charge_pc * k


def test_charge_recovered_negative():
    trace = make_trace(-3.0)
    q = psc.evoked_charge(trace, FS, 1000)
    assert q == pytest.approx(-3.0, rel=0.05)


def test_charge_recovered_positive():
    trace = make_trace(+2.0)
    q = psc.evoked_charge(trace, FS, 1000)
    assert q == pytest.approx(+2.0, rel=0.05)


def test_baseline_subtraction():
    """A DC offset must not leak into evoked charge."""
    q0 = psc.evoked_charge(make_trace(-3.0, baseline_pa=0.0), FS, 1000)
    q1 = psc.evoked_charge(make_trace(-3.0, baseline_pa=-500.0), FS, 1000)
    assert q0 == pytest.approx(q1, rel=0.02)


def test_mono_window_excludes_late_component():
    """A PSC arriving at 30 ms lands in the total window, not the mono one."""
    late = make_trace(-3.0, baseline_pa=0.0)
    shift = int(0.027 * FS)
    late = np.roll(late, shift)
    late[:shift] = 0.0
    q_mono = psc.evoked_charge(late, FS, 1000, psc.MONO_WINDOW_S)
    q_total = psc.evoked_charge(late, FS, 1000, psc.TOTAL_WINDOW_S)
    assert abs(q_mono) < 0.3
    assert q_total == pytest.approx(-3.0, rel=0.15)


def test_peak_amplitude_sign():
    assert psc.peak_amplitude(make_trace(-3.0), FS, 1000) < 0
    assert psc.peak_amplitude(make_trace(+3.0), FS, 1000) > 0
