# slice-ephys-mapping: PPSF + random-ensemble E/I mapping in slices

MATLAB control (packages `+sem` and `+patchclamp`) + Python analysis for
slice patch-clamp experiments driven by the lab's DMD temporal-focusing
photostimulation system, with an acquisition GUI (`sem.gui.AcqWindow`) for patching
and running the mapping blocks. Two experiments:

1. **`exp_slice_ppsf`** — rigorous PPSF of the patched cell: subthreshold
   depolarization + spiking vs laser power × spot offset × DMD fill factor
   (current clamp).
2. **`exp_ensemble_ei`** — thousands of seeded random ensembles of opsin+
   somata; the IDENTICAL ensemble set replayed across clamp blocks (CC,
   VC −70 mV → E, VC +10 mV → I) so E and I pair per ensemble; Python ridge
   regression recovers per-cell weights onto the patched target, then E/I
   coupling analysis.

## ⚠️ Hard rules

- **The DMD repo is a read-only library.** `sem_setup.m` addpaths
  `~/code/DMD-control-flow-software/src` (override:
  `configs/dmd_repo_path_local.m`). NEVER write into that repo from here;
  its `tfp.*` API surface is contracted in [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md)
  and tripwired by `tests/test_tfp_api_surface.m`. It must be a FULL
  checkout (safety caps read its `docs/optics_handoff.md` at runtime).
- **Mock-first is the architecture** (inherited from the DMD repo): all code
  runs end-to-end on macOS against `sem.hardware.MockEphysDAQ` +
  `tfp.hardware.MockDMD`. The exit test is the **mock roundtrip**: simulate
  a session from known weights (`scripts/run_mock_session.m`), Python must
  recover them (`analysis/tests/test_mock_roundtrip.py`).
- **Never bypass `tfp.hardware.DMD.assertPatternsSafe`** (50% on-fraction
  cap, enforced on every pattern load, mock included).
- **Unit conversions live in exactly two mirrored files**:
  `src/+sem/+util/Units.m` and `analysis/src/slice_ephys_analysis/units.py`.
  Change them together. Raw `aiData` stays in DAQ VOLTS on disk; the gains
  snapshot in `metadata.ephys` is the single conversion source.
- **`ensembles.mat` is the design-matrix source of truth** — analysis never
  reconstructs membership from DMD patterns. Patterns are reproduced (not
  stored) from `ensembleSeed(i)` via `fillFactorEnsemble`'s `rngSeed`.

## Conventions (mirror the DMD repo)

- Error IDs `sem:module:class:reason`; contract-level DAQ errors reuse the
  shared `tfp:hardware:DAQ:*` IDs.
- `sem.util.configField(s, name, default)` for ALL config reads.
- Configs parse with `tfp.io.loadConfig` (hand parser): **flat sections,
  one nesting level, no flow maps** — hence `sealTest_preMs`, not nested.
  `hardwareKind: mock|real` is mandatory.
- Coordinates: DMD pixels `[col row]`, 1-indexed, origin top-left.
- Tests: class-based `matlab.unittest`, `tests/test_<subject>.m`, tempname
  fixtures, local helper functions at the bottom of the file. Run with
  `/Applications/MATLAB_R2023a.app/bin/matlab -nodisplay -batch "runtests"`
  (never without `-nodisplay`; tests must not pop windows).
- Mocks are real classes with `getLog()` returning
  `{timestamp, eventType, payload}`.
- `RandStream`/`rng` seeds must stay < 2^32: derive sub-seeds with
  `mod(..., 2^31)`.
- `data/` is gitignored; per-machine overrides use the
  `<name>_local.m.example` pattern.
- No MATLAB `string`/`datetime`/`table` in any saved field Python reads
  (v7.3 opacity — see [docs/DATA_SCHEMA.md](docs/DATA_SCHEMA.md)).

## Key design decisions (why, not just what)

- **Direct-DAQ `EpisodicRunner`, not `tfp.trial.Sequencer`**: the Sequencer
  drives one AO channel (we clock laser + Multiclamp command together —
  `queueClockedAO` is natively multi-channel), treats powerMw as volts, and
  rethrows on any trial failure (fatal mid-patch; we mark-failed and
  continue, aborting only on `^(sem|tfp):hardware:` errors). Precedent:
  the DMD repo's own `exp_ensemble_activation`.
- **The AMPLIFIER controls holding, everywhere.** The MultiClamp Commander
  applies it; `ao_cellCommand` carries only DEVIATIONS and rests at 0, so the
  NI AO idling at its last written sample leaves the cell at holding. Software
  reads holding through `MultiClamp.getHolding` and writes it only on an
  explicit request — the GUI's -70/+10 mV buttons, or a block declaring the
  holding it needs. Software must never emit holding on the AO as well, or a
  cell held at -70 sits at -140. VC↔IC MODE switches stay manual (operator
  prompt). Verify the AO idle behavior on the rig (`verify_wiring.m` step 2).
- **Targeting has NO camera**: opsin+ somata are imaged with 2p/ScanImage
  (red-FP tag), segmented in external software, imported as scan-field
  centroids (`sem.targeting.importSegmentation`), and mapped to DMD pixels
  via `inv(dmdToScan_affine)` from the DMD repo's two-step calibration.
- **Per-cell power = fill factor** (`tfp.patterns.fillFactorEnsemble`), one
  fixed laser voltage per session; the design matrix X holds fill fractions.
- **Seal tests are trials** (kind 'sealTest'): block start/end + every
  `ephys.sealTest_everyNTrials`. The AUTHORITATIVE analysis is still
  post-hoc at finalize, from the continuous record; Rs rules go through
  `sealRuleFcn` (warns by default, a modal in the GUI). Inline Rs-abort is
  still a Phase B upgrade.
- **Live in-block traces** come from `peekContinuousAi`, guarded by
  `ismethod` so a DAQ without it just shows nothing. Implemented on
  `MockEphysDAQ`; pending upstream for the real DAQ
  ([docs/UPSTREAM_TFP_PEEK.md](docs/UPSTREAM_TFP_PEEK.md)). Peeked data is
  DISPLAY ONLY — on the mock its noise realization differs from the record.

## Wiring / rig status

The slice scope is NOT the rig in the DMD repo's CLAUDE.md. All channel
assignments are `%VERIFY` placeholders in `configs/slice_rig.yaml` +
[docs/WIRING.md](docs/WIRING.md) until Phase B bringup closes them
(`scripts/verify_wiring.m`). Mock development is unaffected.

## The GUI (`src/+sem/+gui`, `src/+sem/+acq`)

`sem.gui.AcqWindow` is a rebuild of the lab's legacy `Acq` GUI, kept for
reference (with its `.fig`) under
[docs/old patch clamp GUI scripts/](docs/old%20patch%20clamp%20GUI%20scripts/),
for ONE patched cell instead of two.

- **Free-running, not block-planned.** `sem.acq.SweepRunner` repeats sweeps at
  a fixed ISI until Stop. **ISI is onset-to-onset**, the legacy meaning.
  Parameters are re-read at the top of each sweep, so a live edit lands on the
  NEXT sweep and never the one in flight. `acquireOne()` is the deterministic
  single-sweep path — `start()` genuinely free-runs, so it cannot be assumed
  to yield exactly one sweep.
- **Stimulus grammar**: `sem.protocol.pulseTrain` (start ms, N, width ms,
  amplitude, frequency as onset-to-onset period) composed by
  `sem.protocol.sweepWaveform` into [test pulse] + [command train] on the cell
  command and [LED train] on the light line. Trains SUM where they overlap,
  as the legacy `AO0 = testpulse + CCoutput1` did.
- **The two stimulus panels** (`sem.gui.StimPanel`) each carry the full legacy
  parameter set plus stepping. Editing a field does nothing until **Update** —
  that separation is what lets a value be dialled in mid-run.
- **One stepping mechanism** (`SweepRunner.stepSpec`) serves both the F/I
  current family and the LED parameter sweep.
- **The AMPLIFIER owns holding in patch mode.** The experimenter sets it on the
  MultiClamp Commander; software READS it to display and record, and writes it
  only when the operator presses the -70 mV / +10 mV buttons. Those queue a
  request that Start applies, so holding never changes under a sweep in flight.
  Sweep commands are therefore DEVIATIONS from holding, resting at 0.
  `MultiClamp.getHolding/setHolding` is the interface; `ConfigTelegraph` is a
  stand-in until an `MccTelegraph` can really read the Commander, and
  `isHoldingKnown()` distinguishes a read value from an assumed one.
  `EpisodicRunner` follows the same model: it reads the amplifier's holding at
  block start and sets it only to what the block declares, so sweeps and blocks
  can run against the same cell without doubling holding.
- **Channels are configured ONCE per session** by `PatchDaqAdapter`.
  `NI6323_DAQ.configureAnalogInput` APPENDS to the legacy session and nothing
  removes channels; `MockEphysDAQ` assigns, so the mock cannot catch a
  per-sweep reconfigure. The call count is pinned by a test instead.
- **Seal test is inline**: a mode of the same loop with the stimulus stripped,
  so the trends keep filling. Rs / Rin / holding are numeric readouts in the
  trend-strip titles — the legacy GUI had numbers only in a separate window.
- **Mapping** (`sem.gui.MappingWindow`) is launched from the window, as the
  legacy MappingGui button did, and stops the sweep loop first: `NI6323_DAQ`'s
  finite and continuous sessions cannot both be active.
- **`sem.hardware.PatchDaqAdapter`** is the only bridge between cell units and
  DAQ volts on the sweep path; **`ConfigTelegraph`** serves `config.ephys`
  gains through the `MultiClamp` interface (the operator declares the mode —
  there is no MCC telegraph yet).
- Sweeps are saved by `sem.io.saveSweep` in this repo's trial format (DAQ
  volts + gains snapshot, `kind='sweep'`), so the Python pipeline is unchanged.
- `+patchclamp` now supplies only library code (`+hardware` base classes and
  fakes, `+protocol`, `+config`, `+storage`); its GUI was superseded and
  removed.

## Workflow

- MATLAB tests: `matlab -nodisplay -batch "runtests"` (repo root). GUI tests
  are included — `uifigure` works headless here, verified on R2023a/macOS.
- Launch the GUI on mocks: `matlab -r "run(fullfile('scripts','run_gui_mock.m'))"`,
  or just `run(fullfile('scripts','run_gui_mock.m'))` at the MATLAB prompt.
  **Not `-batch`** — that exits MATLAB as soon as the script returns and takes
  the window with it. `-batch` is for tests and headless runs only.
- Python: `cd analysis && .venv/bin/python -m pytest`.
- Full roundtrip: `matlab -nodisplay -batch "run(fullfile('scripts','run_mock_session.m'))"`
  then `cd analysis && .venv/bin/python -m pytest tests/test_mock_roundtrip.py -v`.
- Figures follow the lab figure conventions (PDF + PNG + .code.html,
  fonttype 42, self-contained legends, no-overlap check) — see
  `analysis/src/slice_ephys_analysis/figures.py`.

## Reading order for a fresh session

1. This file.
2. [ARCHITECTURE.md](ARCHITECTURE.md) — modules, block flow, mock synthesis.
3. [docs/DATA_SCHEMA.md](docs/DATA_SCHEMA.md) — what lands on disk.
4. [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md) — the tfp contract, and
   [docs/UPSTREAM_TFP_PEEK.md](docs/UPSTREAM_TFP_PEEK.md) for the one pending
   upstream change (live in-block AI on the real DAQ).
5. `src/+sem/+protocol/EpisodicRunner.m` and `+sim/SliceNetworkModel.m`.
6. `src/+sem/+gui/AcqWindow.m` and `src/+sem/+acq/SweepRunner.m` for the GUI,
   with the legacy original under
   [docs/old patch clamp GUI scripts/](docs/old%20patch%20clamp%20GUI%20scripts/)
   as the design reference.
