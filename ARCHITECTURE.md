# Architecture

MATLAB package `+sem` (control, under `src/`) + Python package
`slice_ephys_analysis` (offline analysis, under `analysis/src/`). The DMD
repo's `tfp` package is a read-only library (path via `sem_setup.m`; contract
in docs/DEPENDENCIES.md).

## Module map

```
src/+sem/
├── +hardware/   MockEphysDAQ (tfp.hardware.DAQ subclass with a patched cell
│                behind the AI), notifyStim/notifyClampState (mock-forwarding
│                no-ops on real DAQs), makeRig (mock|real factory)
├── +sim/        SliceNetworkModel (ground-truth connectivity + passive
│                membrane + evoked synthesis), makeGroundTruthNetwork
├── +targeting/  importSegmentation (csv/mat/array -> centroids),
│                curateTargets (click UI), buildTargets (scanfield -> DMD via
│                inv(dmdToScan_affine)), mockTargets (fabricated FOV)
├── +protocol/   generateEnsembles (seeded design matrix), planBlocks
│                (identical set per block, reshuffled), EpisodicRunner (the
│                block engine), sealTestWaveform
├── +experiments/ exp_slice_ppsf, exp_ensemble_ei
├── +io/         saveTargets/loadTargets, saveEnsembles/loadEnsembles,
│                saveGroundTruth, sliceSessionAi, ephysMeta
├── +analysis/   sealAnalysis (Rs/Ri/holding), quickTrialSummary,
│                liveEphysFigure
└── +util/       Units (cell<->volt conversions), configField,
                 laserVoltsForMw

analysis/src/slice_ephys_analysis/
    io_mat (v7.3 loaders + SessionIndex/Block/Trial), units (mirror of
    Units.m), psc (charge/peak), spikes (CC), design (X,y per block),
    regression (ridge/lasso + CV + permutation null), ei_coupling,
    ppsf (lateral profiles, HWHM), validate (mock roundtrip), figures
```

## One ensemble block, end to end

1. `exp_ensemble_ei` loads/fabricates `targets`, draws `ens =
   generateEnsembles(targets, config, seed)` (membership + per-cell fill
   fractions + per-trial pattern seeds), saves `ensembles.mat`, and expands
   `planBlocks` — the SAME ensembleIds in every block, per-block seeded
   reshuffle.
2. `EpisodicRunner.runBlock` per block:
   - `safetyChecks('arm')`; operator prompt for the amplifier MODE
     (interactive sessions); `notifyClampState` to the mock.
   - `startContinuousSession` (AI = ephys channels; AO = `[ao_laser
     ao_cellCommand]`; DO lines deliberately NOT in the continuous cfg —
     `sendDigitalPulse` uses the other NI session, avoiding the known
     double-reservation gotcha).
   - Holding ramp (~100 ms) on the cell-command column. From here on every
     queued waveform ends at (holding, 0) so the AO idle level keeps the
     cell held between trials.
   - Chunks of `dmd.chunkSize` patterns are rebuilt deterministically
     (`fillFactorEnsemble` with `ensembleSeed(i)`) and preloaded
     (`loadPatternSequence` → `assertPatternsSafe` fires) → `armSequence` →
     per trial: `advanceToPattern` → `notifyStim` → `queueClockedAO([laser
     cell])` returns the onset sample → `Trial.markRunning(onset, fs, t0)`
     → jittered ITI pause → `safetyChecks('check')`.
   - Seal-test trials (kind 'sealTest') at block start/end + every N stim
     trials: command step on the cell column, laser dark, no DMD change.
   - Per-trial failures: `markFailed` + continue; `^(sem|tfp):hardware:`
     errors abort the block. Chunk-level pattern failures abort loudly.
   - `stopContinuousSession` → finalize: `sliceSessionAi` cuts each trial's
     snippet (preS..postS around the onset anchors), `markComplete`,
     `metadata.ephys.stimOnsetSampleInSnippet` set, `tfp.io.saveTrial` per
     trial, seal trials analyzed (`sealAnalysis`) with Rs-rule warnings,
     block `session.mat` written.
3. After all blocks: replay identity asserted (same ensembleId set per
   block).

## Mock synthesis (MockEphysDAQ + SliceNetworkModel)

At `stopContinuousSession` the mock:
1. Reconstructs the cell-command trace across the whole session (waveforms
   pasted at their onsets; hold-last-sample between queues — mirroring real
   NI AO idle), converts volts → cell units, runs the **passive arm**
   (VC: Ohmic steady state + capacitive edge transients via first-order
   IIRs; IC: leaky integrator). Seal tests and holding ramps therefore
   produce recoverable Rs/Ri/DC.
2. Adds the **evoked arm** per stim event (paired to its queue onset):
   per-member optical drive = opsinGain × fill × laserScale × Gaussian
   falloff of stim-disk-to-soma distance (`ppsfSigmaUm` — the ground-truth
   PPSF); stochastic spikes → EPSCs (charge `W_E` pC/spike, release
   failures, mono latency) + population-drive IPSC (`wIGainPc × Σ cI·spikes`,
   disynaptic latency); driving-force scaling makes E inward at −70 and I
   outward at +10; CC integrates currents to Vm + threshold APs. Kind
   'direct' models the patched cell's own photocurrent (PPSF experiments).
3. Adds noise, converts to DAQ volts via the gains snapshot.

`exportGroundTruth` writes `W_E_eff` / `W_I_eff` (expected pC per unit fill
at reference laser volts) — exactly what the Python ridge regression on the
fill-fraction design matrix estimates.

## Analysis flow (Python)

`SessionIndex` loads ensembles + ground truth + blocks (meta/raw joins).
`design.block_design` converts each stim trial's scaled-output snippet to
cell units (per-trial gains snapshot), integrates evoked charge
(baseline-median-subtracted, 2–60 ms window), sign-flips so "more input" is
positive in both E and I blocks, and joins rows to `ens.X` by ensembleId.
`regression.fit_weights` (RidgeCV default) yields per-cell weights + CV R² +
a permutation null band. `ei_coupling` pairs E and I by ensembleId
(correlation, I~E residual outliers, per-cell W_E vs W_I). `validate`
closes the mock roundtrip; `ppsf` builds lateral profiles + HWHM for PPSF
sessions.

## Timing budget (mock realism)

The mock DAQ clock is wall time: a 600-ensemble two-block roundtrip session
runs ~2–4 minutes. On the rig the same code paces at `timing.itiMeanS`
(0.15 s ± jitter → ~6 Hz); DMD chunk reloads (250 patterns) are the only
pauses, ~12 per 3000-ensemble block, tuned in Phase B from measured upload
time.

## Phases

- **A (done, mock-only)**: everything above green on macOS; roundtrip
  thresholds met.
- **B (rig bringup)**: close WIRING %VERIFYs (`verify_wiring.m`), power cal,
  dmdToScan calibration, chunk timing, model cell → patched cell, real
  `exp_slice_ppsf`.
- **C (science)**: real targeting import → pilot (1 cell, ~200 ensembles,
  VC−70) → thousands of ensembles × both holdings → multi-cell E/I coupling.
