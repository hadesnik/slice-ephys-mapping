"""Spike detection and subthreshold metrics for current-clamp traces (mV)."""

from __future__ import annotations

import numpy as np


def detect_spikes(vm: np.ndarray, fs: float,
                  dvdt_threshold_mv_per_ms: float = 20.0,
                  refractory_ms: float = 2.0) -> np.ndarray:
    """Spike onset indices via a dV/dt threshold with a refractory period."""
    dvdt = np.diff(vm) * fs / 1000.0  # mV per ms
    above = np.where(dvdt > dvdt_threshold_mv_per_ms)[0]
    if above.size == 0:
        return np.array([], dtype=int)
    refractory = int(round(refractory_ms / 1000.0 * fs))
    spikes = [int(above[0])]
    for idx in above[1:]:
        if idx - spikes[-1] > refractory:
            spikes.append(int(idx))
    return np.asarray(spikes, dtype=int)


def spike_count(vm: np.ndarray, fs: float, onset_idx: int,
                window_s: tuple[float, float] = (0.0, 0.05)) -> int:
    """Spikes in a post-onset window."""
    i0 = onset_idx + int(round(window_s[0] * fs))
    i1 = min(len(vm), onset_idx + int(round(window_s[1] * fs)))
    if i1 <= i0:
        return 0
    return int(detect_spikes(vm[i0:i1], fs).size)


def subthreshold_area(vm: np.ndarray, fs: float, onset_idx: int,
                      window_s: tuple[float, float] = (0.002, 0.060),
                      spike_blank_mv: float = -20.0) -> float:
    """Depolarization area (mV*s) with supra-threshold samples clipped.

    Samples above spike_blank_mv (AP waveforms) are clipped to the blank
    level so a burst does not dominate the subthreshold integral.
    """
    base = float(np.median(vm[: max(1, onset_idx - 1)]))
    i0 = onset_idx + int(round(window_s[0] * fs))
    i1 = min(len(vm), onset_idx + int(round(window_s[1] * fs)))
    if i1 <= i0:
        return float("nan")
    seg = np.minimum(vm[i0:i1], spike_blank_mv) if base < spike_blank_mv else vm[i0:i1]
    return float(np.sum(seg - base) / fs)
