# Project context for Claude

## What this repo is

A desktop GUI for episodic whole-cell patch-clamp recording. Drives a MultiClamp 700B amplifier and an NI PCIe-6323 DAQ, plus a 0–5 V LED driver for optogenetic stimulation. See `architecture.md` for the full design.

## Who the user is

The repo owner is the researcher building the rig. The *end* users are novice electrophysiologists in his lab who should not have to think about DAQ channels, voltage-to-pA conversions, or sample clocks. Design choices should consistently favor "no surprises for a novice at the rig" over "maximally flexible for a power user."

## Key invariants — do not break these without asking

1. **Units at the GUI boundary are always cell units.** The user thinks in mV, pA, ms, Hz. Conversion to volts-at-the-DAQ happens in exactly one place (`analysis/units.py`), and it depends on the live mode + amplifier gain reported by the telegraph. Anywhere else in the code that does its own conversion is a bug.

2. **AO and AI share a sample clock and start together.** Timing of stimulus relative to recording must be sample-accurate. Never drive AO from one task and AI from another with independent clocks.

3. **The mode (VC vs IC) is owned by the amplifier, not the GUI.** The dropdown reflects the telegraph; it does not command the amplifier. If the user flips the front-panel switch mid-session, the GUI must follow.

4. **Each trial is a self-contained finite DAQ task.** No continuous streaming. This keeps timing analysis simple and matches the episodic experimental design.

5. **Seal-test parameters are not casually editable.** They live in an "advanced" panel, not on the main screen. Changing them invalidates Rs / Ri trends.

## Platform notes

- Development happens on macOS. The rig PC is Windows.
- MATLAB's Data Acquisition Toolbox NI support and the MultiClamp Commander DLL are Windows-only. All code must run on macOS via `FakeBackend` + `FakeTelegraph`.
- Any code path that needs the MCC DLL or NI hardware must be gated by `ispc()` and must not error at file-load time on a Mac.

## Coding conventions (MATLAB)

- **MATLAB R2023a or newer.** Use `arguments` blocks for input validation on public methods.
- **One `classdef` per file**, filename matching the class name exactly. This is enforced by MATLAB and is also the basis for multi-agent file ownership.
- **All code lives under `+patchclamp/`**. Call sites use `patchclamp.hardware.FakeBackend()`, etc.
- **No App Designer `.mlapp` files.** They are partially binary and don't merge across parallel agent workstreams. GUI is built programmatically with `uifigure`/`uipanel`/`uiaxes`.
- **Cell units everywhere user-facing**; conversion to/from DAQ volts is centralized in `+analysis/Units.m` and parameterized by the live telegraph gain.
- **Handle classes for stateful objects** (DAQ backends, runner, GUI panels) — inherit from `handle`. Pass them around explicitly; no globals, no `evalin('base', ...)`.
- **Events for cross-component signaling**: declare `events` on the source class, use `notify()` to fire, `addlistener()` to subscribe.
- **`matlab.unittest`** for tests. `FakeBackend` and `FakeTelegraph` are the default fixtures.
- No emojis in code, comments, or commit messages.
- Comments only when the *why* is non-obvious (an instrument quirk, a subtle timing constraint, a workaround for a 700B firmware behavior). Don't explain what the code does.
- Variable naming: `camelCase` for variables and methods, `PascalCase` for class names, `UPPER_SNAKE` for true constants in a `Constants.m`.

## What not to do

- Don't add a "live continuous" mode. The whole design is episodic; trying to bolt on continuous acquisition complicates trial timing and analysis.
- Don't store raw DAQ volts in HDF5 — store cell-unit values plus the gain that was in effect, so files are self-describing.
- Don't add abstraction layers ("backend manager", "plugin system", etc.) ahead of a concrete second use case. One DAQ, one amplifier, one LED driver.
- Don't add error handling for impossible states (e.g. mode = neither VC nor IC). The amplifier defines the state space.

## Open questions

Tracked in `tasks.md` under "Decisions needed." Do not start implementation tasks that depend on an unresolved decision.
