"""Spike detection on synthetic CC traces with stereotyped APs."""

import numpy as np

from slice_ephys_analysis import spikes

FS = 20000.0


def make_vm(spike_times_s, n=8000, vrest=-65.0):
    vm = np.full(n, vrest) + 0.2 * np.random.default_rng(0).standard_normal(n)
    ap_len = int(0.002 * FS)
    ap = 85.0 * (1 - np.abs(np.linspace(-1, 1, ap_len)))
    for ts in spike_times_s:
        i0 = int(ts * FS)
        vm[i0:i0 + ap_len] += ap[: max(0, min(ap_len, n - i0))]
    return vm


def test_counts_spikes():
    vm = make_vm([0.05, 0.10, 0.15])
    assert spikes.detect_spikes(vm, FS).size == 3


def test_no_spikes_in_noise():
    vm = make_vm([])
    assert spikes.detect_spikes(vm, FS).size == 0


def test_refractory_merges_single_ap():
    """One AP's rising edge must count once, not once per fast sample."""
    vm = make_vm([0.05])
    assert spikes.detect_spikes(vm, FS).size == 1


def test_spike_count_window():
    vm = make_vm([0.05, 0.30])
    onset = int(0.04 * FS)
    assert spikes.spike_count(vm, FS, onset, (0.0, 0.05)) == 1


def test_subthreshold_area_positive_for_depol():
    n = 8000
    vm = np.full(n, -65.0)
    onset = 1000
    vm[onset:onset + int(0.03 * FS)] += 5.0  # 5 mV depol for 30 ms
    area = spikes.subthreshold_area(vm, FS, onset)
    assert area > 0.1
