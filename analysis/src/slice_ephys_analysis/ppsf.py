"""PPSF surfaces from exp_slice_ppsf sessions (CC, direct activation).

Each trial's metadata.extra carries the factorial coordinates (distanceUm,
offsetUm, laserVolts, fillFactor, repIdx); the response metrics come from
the CC trace: peak depolarization, subthreshold area, spike count.
"""

from __future__ import annotations

import numpy as np

from . import spikes, units
from .io_mat import Block


def ppsf_table(block: Block) -> list[dict]:
    """One row per completed 'direct' trial with factorial coords + metrics."""
    rows = []
    for t in block.trials:
        if t.status != "complete" or t.kind != "direct":
            continue
        extra = t.meta.get("metadata", {}).get("extra", {}) or {}
        v = t.scaled_output_volts()
        if v is None:
            continue
        vm = units.scaled_daq_volts_to_cell(v, "IC", t.ephys["gains"])
        onset = t.onset_in_snippet
        base = float(np.median(vm[: max(1, onset - 1)]))
        i1 = min(len(vm), onset + int(round(0.06 * t.fs)))
        seg = vm[onset:i1] - base
        rows.append({
            "distance_um": float(extra.get("distanceUm", float("nan"))),
            "laser_volts": float(extra.get("laserVolts", float("nan"))),
            "fill_factor": float(extra.get("fillFactor", float("nan"))),
            "rep_idx": float(extra.get("repIdx", float("nan"))),
            "peak_depol_mv": float(np.max(seg)) if seg.size else float("nan"),
            "subthreshold_area": spikes.subthreshold_area(vm, t.fs, onset),
            "n_spikes": spikes.spike_count(vm, t.fs, onset),
        })
    return rows


def lateral_profile(rows: list[dict], laser_volts: float, fill_factor: float) -> dict:
    """Mean response vs distance at one (power, fill) condition."""
    sel = [r for r in rows
           if abs(r["laser_volts"] - laser_volts) < 1e-9
           and abs(r["fill_factor"] - fill_factor) < 1e-9]
    d = np.asarray([r["distance_um"] for r in sel])
    resp = np.asarray([r["peak_depol_mv"] for r in sel])
    uniq = np.unique(np.round(d, 3))
    return {
        "distance_um": uniq,
        "mean_peak_mv": np.asarray([np.mean(resp[np.round(d, 3) == u]) for u in uniq]),
        "n": np.asarray([np.sum(np.round(d, 3) == u) for u in uniq]),
    }


def half_width_um(profile: dict) -> float:
    """Half-width at half-maximum of the lateral profile (linear interp)."""
    d, m = profile["distance_um"], profile["mean_peak_mv"]
    order = np.argsort(d)
    d, m = d[order], m[order]
    peak = float(np.max(m))
    if peak <= 0:
        return float("nan")
    half = peak / 2.0
    above = m >= half
    if above.all():
        return float(d[-1])
    last = int(np.where(above)[0].max())
    if last + 1 >= d.size:
        return float(d[-1])
    d0, d1, m0, m1 = d[last], d[last + 1], m[last], m[last + 1]
    if m0 == m1:
        return float(d0)
    return float(d0 + (half - m0) * (d1 - d0) / (m1 - m0))
