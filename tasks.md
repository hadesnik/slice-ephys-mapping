# Tasks

## Decisions — resolved

| #  | Question                                        | Decision                                                                 |
|----|-------------------------------------------------|--------------------------------------------------------------------------|
| Q1 | Read 700B gain from telegraph?                  | **Yes.** Never hard-code. Spec values are FakeTelegraph defaults only.   |
| Q2 | Target OS                                       | **Dev on macOS, deploy on Windows rig PC.** All real-hw code `ispc()`-gated. |
| Q3 | Command pulse-train amplitude units             | **Auto-relabel** "Amplitude (pA)" in IC, "Amplitude (mV)" in VC, driven by telegraph. |
| Q4 | Rs estimation                                   | **Peak-only.** Store the transient so we can refit offline if needed.    |
| Q5 | Sample rate                                     | **20 kHz default**, editable in advanced panel.                          |
| Q6 | HDF5 layout                                     | **One file per session.** New cell → new session. Auto-name from timestamp + cell ID. |
| Q7 | LED units in GUI                                | **0–100 %** (linear to 0–5 V) for v1. Calibration UI is v2.              |
| Q8 | Plots on mode change mid-session                | **Persist with mode tag** (color-coded). Rs plot grays during IC.        |

Language: **MATLAB R2023a+**.

---

## Multi-agent coding plan

### Design principles

- **One MATLAB class = one file = one owner per round.** Files never have two writers in the same round.
- **Rounds are gated.** Round N+1 cannot start until Round N is merged, tests pass, and contracts are frozen.
- **Contracts are frozen at the end of Round 0** (abstract class signatures, struct schemas, event names). Later rounds may extend but not change them — if a change is needed, raise it before the round starts.
- **Each parallel agent works in an isolated git worktree** (`Agent` tool with `isolation: "worktree"`). A short integration step at end of round merges the worktrees and re-runs tests.
- **No agent touches files outside its allocation.** The prompt names every file the agent may create or edit, and explicitly forbids edits elsewhere.

### File-ownership matrix (read before each round)

Every file is owned by exactly one agent per round. The "Owner (Round)" column lists which round introduces or modifies the file.

| File                                            | Round it's written in | Notes                                           |
|-------------------------------------------------|-----------------------|-------------------------------------------------|
| `startup.m`, `runApp.m`                         | R0 (stub) → R5        | Stub in R0, real wiring in R5.                  |
| `+patchclamp/+hardware/DAQ.m` (abstract)        | R0 only               | Frozen after R0.                                |
| `+patchclamp/+hardware/MultiClamp.m` (abstract) | R0 only               | Frozen after R0.                                |
| `+patchclamp/+hardware/LedDriver.m`             | R0                    | Tiny, just a unit converter.                    |
| `+patchclamp/+config/TrialConfig.m`             | R0                    | Schema + `validate()`. Frozen.                  |
| `+patchclamp/+config/PulseTrainConfig.m`        | R0                    | Frozen.                                         |
| `+patchclamp/+analysis/Units.m`                 | R0                    | Cell ↔ DAQ-V. Frozen.                           |
| `+patchclamp/+hardware/FakeBackend.m`           | R1 Agent A            |                                                 |
| `+patchclamp/+hardware/FakeTelegraph.m`         | R1 Agent A            |                                                 |
| `+patchclamp/+protocol/SealTest.m`              | R1 Agent B            |                                                 |
| `+patchclamp/+protocol/PulseTrain.m`            | R1 Agent B            |                                                 |
| `+patchclamp/+protocol/Trial.m`                 | R1 Agent B            |                                                 |
| `+patchclamp/+analysis/Seal.m`                  | R1 Agent C            | Pure function on a trial result.                |
| `+patchclamp/+storage/Hdf5Writer.m`             | R1 Agent D            |                                                 |
| `tests/Round1_*.m`                              | R1 (each agent ships tests for its own files) | |
| `+patchclamp/+acquisition/ExperimentRunner.m`   | R2 (single agent)     | Integration seam — serial.                      |
| `+patchclamp/+gui/MainWindow.m`                 | R3 Agent I            | Built after panels exist.                       |
| `+patchclamp/+gui/ControlsPanel.m`              | R3 Agent F            |                                                 |
| `+patchclamp/+gui/TrialPlotPanel.m`             | R3 Agent G            |                                                 |
| `+patchclamp/+gui/TrendPlotsPanel.m`            | R3 Agent G            |                                                 |
| `+patchclamp/+gui/OptoEditorPanel.m`            | R3 Agent H            |                                                 |
| `+patchclamp/+gui/CommandEditorPanel.m`         | R3 Agent H            |                                                 |
| `+patchclamp/+hardware/NidaqBackend.m`          | R4 (rig PC)           |                                                 |
| `+patchclamp/+hardware/MccTelegraph.m`          | R4 (rig PC)           |                                                 |

---

### Round 0 — Scaffolding (single agent, serial) [~half a day]

**Goal:** lock down the interface contracts so the parallel rounds can proceed without merge conflicts.

One agent, no parallelism. Deliverables:
1. Repo skeleton: `+patchclamp/` package directories, `tests/`, `startup.m`, `runApp.m` (stub: prints "TODO"), `.gitignore` (MATLAB defaults), `README.md`.
2. Abstract classes with full method signatures, `arguments` blocks, and doc-comments — but no logic:
   - `+patchclamp/+hardware/DAQ.m` — `configureTrial`, `run`, `cleanup`
   - `+patchclamp/+hardware/MultiClamp.m` — `getMode`, `getGain`, `events: ModeChanged, GainChanged`
3. Config schemas with `validate()` methods:
   - `+patchclamp/+config/TrialConfig.m`
   - `+patchclamp/+config/PulseTrainConfig.m`
4. `+patchclamp/+analysis/Units.m` — static methods `cellToDaqVolts(value, mode, gain)`, `daqVoltsToCell(volts, mode, gain)`. **Implemented** (not a stub) because everyone uses it. Includes unit tests.
5. `+patchclamp/+hardware/LedDriver.m` — `brightnessPercentToVolts()` etc. Implemented.
6. A `tests/SmokeTest.m` that just verifies the package loads on macOS.

**Exit criterion:** `runtests('tests')` passes on macOS. Contracts (abstract class signatures, struct fields, event names) are frozen — open a "Contracts v1" tag.

---

### Round 1 — Parallel implementations (4 agents in worktrees) [~1–2 days each]

All four agents run **in parallel**, each in its own git worktree. They depend only on Round 0 contracts, not on each other.

- **Agent A — Fake hardware**
  Files: `+hardware/FakeBackend.m`, `+hardware/FakeTelegraph.m`, `tests/Round1_FakeBackend.m`.
  Task: synthesize a realistic AI trace = baseline + RC response to AO0 + injected opto artifact + Gaussian noise. Tunable ground-truth Rs/Ri/Cm/Vrest so Agent C's analysis can be validated. FakeTelegraph emits programmable mode/gain and fires the contract events.

- **Agent B — Protocol generation**
  Files: `+protocol/SealTest.m`, `+protocol/PulseTrain.m`, `+protocol/Trial.m`, `tests/Round1_Protocol.m`.
  Task: build AO0 (command) and AO2 (LED) waveforms in cell units, given a `TrialConfig`. `SealTest` produces the 0–200 ms segment. `PulseTrain` validates that `nPulses × (1/freq)` fits the stimulus window and errors clearly otherwise. `Trial.compose()` returns the full AO0 + AO2 arrays.

- **Agent C — Analysis**
  Files: `+analysis/Seal.m`, `tests/Round1_Analysis.m`.
  Task: pure function, takes a trial result struct (AI samples + mode + gain + stim metadata), returns `rsMohm`, `riMohm`, `holding`. Peak-only Rs. Tests validate against the FakeBackend's ground-truth Rs/Ri/Vrest (Agent A's tunables). Coordinate with Agent A only on test fixtures.

- **Agent D — Storage**
  Files: `+storage/Hdf5Writer.m`, `tests/Round1_Storage.m`.
  Task: open a session file, append trials, store gain snapshots, write meta. Idempotent close. Verify by reading back with `h5read` and comparing.

**Coordination during R1:**
- Agents A and C must agree on the trial-result struct used as input to analysis — but that struct is already defined in `architecture.md §7`. No deviation without a meeting.
- All four ship `matlab.unittest` test classes alongside their code.

**Exit criterion:** all four worktrees merge cleanly into main. `runtests('tests')` green on macOS. Contracts unchanged.

---

### Round 2 — Acquisition engine (single agent, serial) [~1 day]

**Goal:** the seam where everything from R1 connects. Serial because it touches all R1 outputs.

Files: `+acquisition/ExperimentRunner.m`, `tests/Round2_Runner.m`.

Task:
- Takes a `DAQ`, a `MultiClamp`, a `Hdf5Writer`, and a `TrialConfig`.
- State machine: Idle → Running → Stopping → Idle.
- Per trial: ask Protocol for AO waveforms, hand to DAQ, await AI, run Analysis, emit `TrialFinished` event, append to writer, schedule next trial after ITI via `timer`.
- Listens to `FakeTelegraph` (or real) for `ModeChanged` / `GainChanged` and updates internal state. Mode change mid-session is tagged on subsequent trials, not retroactively.

End-to-end smoke test: 5 trials with FakeBackend → HDF5 file on disk with 5 trial groups, Rs/Ri within tolerance of ground truth, no leaked timers.

**Exit criterion:** smoke test passes; can run a fake session headlessly from a script.

---

### Round 3 — GUI (3 parallel panel agents → 1 assembly agent) [~2 days]

GUI is built programmatically with `uifigure`. Each *panel* is its own `classdef` returning a configured `uipanel` and exposing handles for the assembly. Panels are independent so they can be parallel; the assembly happens at the end.

**Round 3a (parallel, 3 agents):**

- **Agent F — Controls**
  Files: `+gui/ControlsPanel.m`, `tests/Round3_ControlsPanel.m`.
  Start / Stop buttons, ITI field, trial length field, mode label (read-only mirror), cell ID field, status line for current gain. Tests use `uitest`-style scripted clicks.

- **Agent G — Plots**
  Files: `+gui/TrialPlotPanel.m`, `+gui/TrendPlotsPanel.m`, `tests/Round3_Plots.m`.
  Trial overlay (last N faded), Rs/Ri/Holding trends. Subscribes to `TrialFinished` events. Mode-aware: Rs plot grays out in IC; holding label flips between "Holding (pA)" and "Vrest (mV)".

- **Agent H — Stimulus editors**
  Files: `+gui/OptoEditorPanel.m`, `+gui/CommandEditorPanel.m`, `tests/Round3_Editors.m`.
  Four numeric fields + Update button + preview `uiaxes`. Command editor's amplitude label is **mode-driven** (Q3). Update button validates with the same code path the runner uses, so errors are caught early.

**Round 3b (serial, 1 agent, after 3a merges):**

- **Agent I — MainWindow assembly**
  Files: `+gui/MainWindow.m`, `runApp.m` (final), `tests/Round3_MainWindow.m`.
  Lays out the panels, wires their signals to a real `ExperimentRunner` running against `FakeBackend`. Manual checklist + automated smoke test (open figure, click Start, verify N trials, click Stop, close cleanly).

**Exit criterion:** end-to-end with FakeBackend on macOS — click Start, watch plots update, click Stop, find a valid HDF5 file on disk.

---

### Round 4 — Real hardware (rig PC only) [~1 day on the rig]

Files: `+hardware/NidaqBackend.m`, `+hardware/MccTelegraph.m`, `tests/Round4_HardwareSmoke.m`.

Single agent (or pair-programming live with the rig). Cannot run on Mac.

- `NidaqBackend` mirrors the FakeBackend contract using Data Acquisition Toolbox (`daq("ni")`). Hardware-timed AO/AI on a shared clock, start trigger so AO and AI go simultaneously.
- `MccTelegraph` wraps `AxMultiClampMsg.dll` via `NET.addAssembly` (preferred) or `loadlibrary`. Polls mode + gain at ~5 Hz, fires events on change.
- Smoke test: short signal loopback (AO → AI via a BNC) confirms timing alignment within 1 sample; mode toggle on the 700B front panel shows up in the GUI within 200 ms.

**Exit criterion:** can record a real cell, see live Rs/Ri, save HDF5.

---

### Round 5 — Polish (1 agent) [~1 day]

Files: README screenshots, `+config/` save/load (JSON), crash-recovery flush in `Hdf5Writer`, first-run checklist.

---

## Estimated path to "first real recording"

Round 0 (half day) → Round 1 (1–2 days parallel) → Round 2 (1 day) → Round 3 (2 days, mostly parallel) → Round 4 (1 day on rig) ≈ **5–7 working days**, of which the rig PC is needed only at the end.

---

## Deferred (post-v1)

- Arbitrary waveform stimuli (continuous functions, mentioned in spec §9).
- LED power calibration UI.
- Online spike detection.
- Multi-electrode support.
- Post-hoc analysis GUI.
