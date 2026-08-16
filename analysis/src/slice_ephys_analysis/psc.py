"""Postsynaptic-current quantification on single-trial snippets.

Conventions:
- Input traces are in CELL UNITS (pA for VC) — convert with units.py first.
- Charge integrates (trace - baseline) over a post-onset window; pA * s = pC.
- Sign is preserved: evoked E at -70 mV gives NEGATIVE (inward) charge,
  evoked I at +10 mV gives POSITIVE (outward) charge. The regression layer
  flips signs so weights are positive (design.py).
- Windows (seconds, relative to stim onset): the monosynaptic window
  captures direct connections (spike latency + synaptic delay), the total
  window includes polysynaptic components.
"""

from __future__ import annotations

import numpy as np

MONO_WINDOW_S = (0.002, 0.015)
TOTAL_WINDOW_S = (0.002, 0.060)


def baseline(trace: np.ndarray, onset_idx: int) -> float:
    """Median of the pre-onset segment (robust to a stray event)."""
    b = trace[: max(1, onset_idx - 1)]
    return float(np.median(b))


def evoked_charge(trace: np.ndarray, fs: float, onset_idx: int,
                  window_s: tuple[float, float] = TOTAL_WINDOW_S) -> float:
    """Signed evoked charge (pC) in a post-onset window, baseline-subtracted."""
    base = baseline(trace, onset_idx)
    i0 = onset_idx + int(round(window_s[0] * fs))
    i1 = min(len(trace), onset_idx + int(round(window_s[1] * fs)))
    if i1 <= i0:
        return float("nan")
    return float(np.sum(trace[i0:i1] - base) / fs)


def peak_amplitude(trace: np.ndarray, fs: float, onset_idx: int,
                   window_s: tuple[float, float] = TOTAL_WINDOW_S) -> float:
    """Signed peak deviation from baseline in the window (cell units)."""
    base = baseline(trace, onset_idx)
    i0 = onset_idx + int(round(window_s[0] * fs))
    i1 = min(len(trace), onset_idx + int(round(window_s[1] * fs)))
    if i1 <= i0:
        return float("nan")
    seg = trace[i0:i1] - base
    return float(seg[np.argmax(np.abs(seg))])
