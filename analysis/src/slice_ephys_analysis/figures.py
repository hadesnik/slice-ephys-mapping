"""Publication figures for slice-ephys-mapping sessions.

Every figure here follows the lab figure standards (enforced by
figure_helpers, bundled from the figure-standards plugin): vector PDF with
embedded editable text (fonttype 42) + PNG companion + clickable .code.html
source listing, sorted into pdf/ png/ html/ subfolders; bold-titled
self-contained 10 pt legend with per-panel descriptions; 14 pt panel
letters; a programmatic text-overlap check at save time that must be clean
before a figure counts as done.

Current figures:
  roundtrip_figure(session_dir, outdir)  — the mock-roundtrip validation:
      recovered vs ground-truth W_E / W_I, grand-average evoked traces at
      both holdings, and per-ensemble E/I coupling. Run as
      `python -m slice_ephys_analysis.figures <session_dir>` after
      scripts/run_mock_session.m.

Real-data figures (PPSF surfaces, E/I coupling across cells) are added in
Phase C alongside the first real sessions.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np

from . import design, ei_coupling, psc, regression, units, validate
from .figure_helpers import apply_style, justified_legend, panel_label, savefig
from .io_mat import SessionIndex


def _mean_evoked_trace(block, window_s: float = 0.08):
    """Grand-average evoked scaled-output trace (pA) around stim onset."""
    traces = []
    n_pre = None
    for t in block.stim_trials():
        v = t.scaled_output_volts()
        if v is None:
            continue
        trace = units.scaled_daq_volts_to_cell(v, "VC", t.ephys["gains"])
        onset = t.onset_in_snippet
        fs = t.fs
        pre = int(0.02 * fs)
        post = int(window_s * fs)
        if onset - pre < 0 or onset + post > trace.size:
            continue
        seg = trace[onset - pre:onset + post]
        seg = seg - np.median(seg[:pre])
        traces.append(seg)
        n_pre = pre
    if not traces:
        return None, None, None
    m = np.mean(np.vstack(traces), axis=0)
    fs = block.stim_trials()[0].fs
    tax = (np.arange(m.size) - n_pre) / fs * 1000.0  # ms relative to onset
    return tax, m, len(traces)


def roundtrip_figure(session_dir: str | Path, outdir: str | Path = "figures/roundtrip"):
    """Build the mock-roundtrip validation figure for one session."""
    import matplotlib.pyplot as plt

    apply_style()
    session_dir = Path(session_dir)

    idx = SessionIndex(session_dir)
    gt = idx.ground_truth
    if gt is None:
        raise FileNotFoundError(f"{session_dir} has no ground_truth.mat")
    res = validate.validate_session(session_dir)

    block_e = idx.block_by_holding(-70.0)
    block_i = idx.block_by_holding(10.0)
    d_e = design.average_repeats(design.block_design(block_e, idx.ensembles))
    d_i = design.average_repeats(design.block_design(block_i, idx.ensembles))
    paired = ei_coupling.pair_by_ensemble(d_e, d_i)
    stats = ei_coupling.coupling_stats(paired)

    fig, axes = plt.subplots(2, 2, figsize=(9.0, 8.6))
    fig.subplots_adjust(bottom=0.30, hspace=0.42, wspace=0.32,
                        left=0.09, right=0.97, top=0.95)
    ax_a, ax_b, ax_c, ax_d = axes.flatten()

    # Panels A/B compare the same quantity (pC per unit fill) -> shared limits.
    measurable_e = np.any(d_e["X"] > 0, axis=0)
    lim = 1.1 * max(
        float(np.max(gt["W_E_eff"][measurable_e])), float(np.max(res["e"]["w"])),
        float(np.max(gt["W_I_eff"][measurable_e])), float(np.max(res["i"]["w"])), 1.0)

    for ax, key, w_true, color, label in (
            (ax_a, "e", gt["W_E_eff"], "#1f77b4", "excitation (VC −70 mV)"),
            (ax_b, "i", gt["W_I_eff"], "#d62728", "inhibition (VC +10 mV)")):
        w = res[key]["w"]
        connected = (w_true > 1e-12) & measurable_e
        zero = (w_true <= 1e-12) & measurable_e
        ax.plot([0, lim], [0, lim], "-", color="0.75", lw=1, zorder=1)
        ax.scatter(w_true[connected], w[connected], s=36, color=color,
                   label="connected", zorder=3)
        ax.scatter(w_true[zero], w[zero], s=28, facecolor="none",
                   edgecolor="0.4", label="zero-weight / opsin−", zorder=2)
        ax.set_xlim(-0.05 * lim, lim)
        ax.set_ylim(-0.05 * lim, lim)
        ax.set_xlabel("true weight (pC per unit fill)")
        ax.set_ylabel("recovered weight (pC per unit fill)")
        ax.set_title(label, fontsize=10)
        ax.text(0.05, 0.90, f"r = {res[key]['r_connected']:.2f}",
                transform=ax.transAxes, fontsize=9)
        ax.legend(fontsize=8, loc="lower right", frameon=False)

    # Panel C: grand-average evoked traces at both holdings.
    tax_e, m_e, n_e = _mean_evoked_trace(block_e)
    tax_i, m_i, n_i = _mean_evoked_trace(block_i)
    ax_c.axvline(0, color="0.8", lw=0.8)
    ax_c.plot(tax_e, m_e, color="#1f77b4", lw=1.2,
              label=f"VC −70 mV (n = {n_e})")
    ax_c.plot(tax_i, m_i, color="#d62728", lw=1.2,
              label=f"VC +10 mV (n = {n_i})")
    ax_c.axhline(0, color="0.85", lw=0.8)
    ax_c.set_xlabel("time from stim onset (ms)")
    ax_c.set_ylabel("evoked current (pA)")
    ax_c.legend(fontsize=8, frameon=False, loc="lower right")

    # Panel D: per-ensemble E vs I coupling.
    ax_d.scatter(paired["e"], paired["i"], s=12, color="0.35", alpha=0.6)
    xfit = np.linspace(float(np.min(paired["e"])), float(np.max(paired["e"])), 10)
    ax_d.plot(xfit, stats["slope"] * xfit + stats["intercept"], "-",
              color="#2ca02c", lw=1.4)
    ax_d.set_xlabel("evoked E charge (pC, VC −70 mV)")
    ax_d.set_ylabel("evoked I charge (pC, VC +10 mV)")
    ax_d.text(0.05, 0.90, f"r = {stats['r']:.2f}", transform=ax_d.transAxes,
              fontsize=9)

    for ax, letter in ((ax_a, "A"), (ax_b, "B"), (ax_c, "C"), (ax_d, "D")):
        panel_label(ax, letter)

    justified_legend(
        fig,
        "Mock-roundtrip validation: known synaptic weights are recovered from a "
        "simulated ensemble E/I mapping session.",
        f"(A) Recovered vs ground-truth excitatory weight per candidate cell "
        f"(pC of evoked charge per unit fill fraction), ridge regression on the "
        f"{d_e['y'].size}-ensemble fill-fraction design matrix at −70 mV "
        f"holding; filled symbols are truly connected cells, open symbols "
        f"zero-weight or opsin− cells, gray line is unity; the never-"
        f"stimulated patched cell is excluded. (B) Same for the inhibitory "
        f"pathway at +10 mV holding. Panels A and B share identical axis "
        f"limits. (C) Grand-average baseline-subtracted evoked current across "
        f"all ensemble trials, aligned to stimulus onset: net inward at "
        f"−70 mV (excitation) and net outward at +10 mV (inhibition). "
        f"(D) Per-ensemble evoked E charge vs evoked I charge, paired by "
        f"ensembleId across the two holding blocks (sign-corrected so larger "
        f"means more input; charge integrated 2–60 ms after onset, "
        f"baseline = pre-onset median), with the linear I~E fit (green). "
        f"Session {session_dir.name}, seed {int(gt['seed'])}.")

    savefig(fig, "mock_roundtrip_validation", outdir=str(outdir), functions=[
        roundtrip_figure, _mean_evoked_trace,
        validate.validate_session, design.block_design, design.average_repeats,
        regression.fit_weights, ei_coupling.pair_by_ensemble,
        ei_coupling.coupling_stats, psc.evoked_charge,
        units.scaled_daq_volts_to_cell, justified_legend, panel_label,
    ], strict=True)
    plt.close(fig)
    return Path(outdir)


if __name__ == "__main__":
    session = sys.argv[1] if len(sys.argv) > 1 else None
    if session is None:
        repo = Path(__file__).resolve().parents[3]
        candidates = sorted((repo / "data").glob("mock_session_*"))
        if not candidates:
            raise SystemExit("no mock session found; run scripts/run_mock_session.m")
        session = candidates[-1]
    out = Path(__file__).resolve().parents[3] / "figures" / "roundtrip"
    roundtrip_figure(session, out)
    print(f"figure written under {out}")
