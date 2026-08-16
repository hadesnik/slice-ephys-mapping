"""slice_ephys_analysis: offline analysis for slice-ephys-mapping sessions.

MATLAB (the `sem` package) runs the rig and writes .mat (v7.3) sessions;
this package reads them (io_mat), converts DAQ volts to cell units exactly
once (units, mirroring sem.util.Units), quantifies PSCs and spikes (psc,
spikes), builds the regression design from ensembles.mat (design), estimates
per-cell weights onto the patched target (regression), and analyzes E/I
coupling across ensembles (ei_coupling). validate closes the mock roundtrip
against ground_truth.mat.
"""

__version__ = "0.1.0"
