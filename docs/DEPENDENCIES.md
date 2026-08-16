# The tfp contract

This repo consumes the DMD control repo (`DMD-control-flow-software`, MATLAB
package `tfp`) as a library. `sem_setup.m` adds `<dmdRepo>/src` to the path —
it must be a **full checkout**, because `tfp.util.readHandoffConstants`
resolves `<dmdRepo>/docs/optics_handoff.md` from its own file location and
`tfp.hardware.DMD.assertPatternsSafe` reads it on **every** pattern upload
(the 50% on-fraction air-breakdown cap; mock included, never bypass).

The dependency is **one-way and read-only**: sem never writes into the DMD
repo. `tests/test_tfp_api_surface.m` is the tripwire — every entry point
listed here has an existence check there, plus behavioral spot-checks on the
starred contracts. If an upstream refactor breaks a name, the suite goes red
here instead of failing on a rig day.

## Entry points used

### Hardware
| Entry point | Used for |
|---|---|
| `tfp.hardware.DAQ` (abstract) | `sem.hardware.MockEphysDAQ` subclasses it; contract errors reuse the shared `tfp:hardware:DAQ:*` identifiers |
| `startContinuousSession(cfg)` / `stopContinuousSession()` | one hardware-clocked session per block; per-trial AI sliced post-hoc |
| ★ `queueClockedAO(samples, rate, 'immediate')` | **nSamples × nAo** — laser + cell-command on one clock (the reason no Sequencer change is needed) |
| `currentSampleIndex()`, `sendDigitalPulse`, `configureDigitalOutput`, `outputSingleAnalog` | onset anchors, do_sync marker, bringup scripts |
| `tfp.hardware.NI6323_DAQ` | the real DAQ (Phase B; board name %VERIFY) |
| `tfp.hardware.MockDMD` / `DLP650LNIR_DMD` | DMD backends via `sem.hardware.makeRig` |
| ★ `DMD.loadPatternSequence(patterns, opts)` + `assertPatternsSafe` | chunked pattern preload; the safety cap fires inside |
| `DMD.armSequence` / `advanceToPattern(idx)` | per-trial pattern switch (episodic idiom from `exp_ensemble_activation`) |

### Trial + IO
| Entry point | Used for |
|---|---|
| `tfp.trial.Trial` (`markRunning(onset, fs, t0)` / `markComplete(data, offset)` / `markFailed`) | trial state machine + DAQ sample anchors |
| ★ `tfp.io.saveTrial(trial, dataDir)` | schema v2 (`trial_%04d_meta/_raw.mat`); ephys schema rides in `metadata.ephys` (meta) + `data.aiData` (raw, whitelisted) |
| `tfp.io.sessionLog(dir, event, payload)` | TSV session log |
| `tfp.io.loadConfig(yamlPath)` | hand YAML parser — **flat sections, one nesting level, `hardwareKind` required** |
| `tfp.io.saveCalibration` / `loadCalibration` | power curve + dmdToScan affine files |
| `tfp.io.receiveROIsFromScanImage` / `parseRoiPayload` | optional live centroid delivery (msocket port 3045) |

### Patterns + sequences
| Entry point | Used for |
|---|---|
| ★ `tfp.patterns.fillFactorEnsemble(dmd, centroids, radiusPx, fills, opts)` | the per-cell power knob; `opts.rngSeed` makes patterns reproducible from `ensembleSeed`, `opts.permutations` gives nested subsets |
| `tfp.patterns.singleSpot` / `multiSpot` / `calibratedAffine` | bringup + alternate targeting paths |
| `tfp.trial.TrialSequence.gaussianGrid2D(maxUm, n, sigma)` | PPSF offset grid ((2n+1)² points, dense near soma) |

### Calibration + analysis + util
| Entry point | Used for |
|---|---|
| `tfp.calibration.powerMeterSweep` | volts→mW curve (`sem.util.laserVoltsForMw` consumes it) |
| `tfp.calibration.alignDMDtoCamera` | Step A of the two-step dmdToScan calibration |
| `tfp.analysis.responseClassifier` | generic threshold classifier (sign-wrap for inward currents) |
| `tfp.util.configField`, `tfp.util.safetyChecks('arm'/'check')` | config reads; per-trial abort gate |
| ★ `tfp.util.readHandoffConstants` | indirect (via assertPatternsSafe); requires the full checkout |

## Known upstream constraints inherited

- `loadConfig` cannot parse nested maps beyond one level → all sem config
  sections are flat (`sealTest_preMs`, not `sealTest: {preMs: ...}`).
- `saveTrial`'s raw whitelist is hardcoded (`aiData`, `frameClock`, ... ) —
  anything else on `trial.data` is silently dropped. sem stores the snippet
  in `aiData` and everything else in `metadata`.
- `NI6323_DAQ`'s continuous AI buffer grows O(n²) (listener concat). Gated
  upstream fix: profile a ~7 min 20 kHz block in Phase B first.
- `RandStream`/`rng` seeds must be < 2³² — sem derives sub-seeds with
  `mod(..., 2^31)`.
