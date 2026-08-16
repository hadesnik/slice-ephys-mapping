# Slice-rig wiring (Phase B)

**Status: NOTHING VERIFIED.** This scope is NOT the rig documented in the DMD
repo's CLAUDE.md — that wiring table does not apply here. Every row below is
a placeholder mirroring `configs/slice_rig.yaml`; close each `%VERIFY` by
physically confirming the wire (`scripts/verify_wiring.m` walks the checks),
then update BOTH this table and the YAML, deleting the marker. The config
test (`test_config_examples/slice_rig_keeps_verify_markers`) intentionally
fails if markers vanish without this file changing.

## NI channel map (board name %VERIFY: `Dev1`)

| Line | Dir | Connected to | Config key | Status |
|---|---|---|---|---|
| ai0 | in | Multiclamp 700B SCALED OUTPUT | `daq.ai_scaledOutput` | %VERIFY |
| ai1 | in | 700B command monitor (optional) | `daq.ai_commandMonitor` | %VERIFY |
| ao0 | out | Laser power modulation input | `daq.ao_laser` | %VERIFY |
| ao1 | out | 700B EXT COMMAND input | `daq.ao_cellCommand` | %VERIFY |
| port0/line0 | out | Session-boundary marker (operator scope) | `daq.do_sync` | %VERIFY |

## Amplifier scaling (700B)

| Quantity | Value | Config key | Status |
|---|---|---|---|
| EXT COMMAND, VC | 20 mV/V | `ephys.commandVcMvPerV` | physical constant |
| EXT COMMAND, IC | 400 pA/V | `ephys.commandIcPaPerV` | physical constant |
| SCALED OUTPUT gain, VC | 1000 pA/V (assumed) | `ephys.scaledVcPaPerV` | %VERIFY front panel |
| SCALED OUTPUT gain, IC | 20 mV/mV (assumed) | `ephys.scaledIcMvPerMv` | %VERIFY front panel |

**Software-holding preconditions** (design decisions, verified in
`verify_wiring.m` step 2):

1. MultiClamp **Commander holding = 0** in every block — the block holding
   (−70 / +10 mV) is commanded entirely through `ao_cellCommand`; the value
   recorded in `metadata.ephys.holdingMv` assumes it.
2. The NI AO **idles at the last written sample** after a queued waveform
   drains — every sem waveform ends with cell-command at holding and laser
   at 0, which is what keeps the cell held between trials. If this board
   config does not hold the last sample, STOP: the holding design is unsafe.

## Laser

| Item | Value | Status |
|---|---|---|
| Modulation input range | 0–5 V (`laser.ao_voltage_max`) | %VERIFY |
| Volts → mW at sample | `laser.calibration_file` via `run_power_calibration.m` | %VERIFY |

## DMD

| Item | Value | Status |
|---|---|---|
| Board / ALP version | DLP7000 via ALP-4.1 assumed (`dmd.alpVersion`) | %VERIFY |
| Geometry | 768 × 1024 assumed (`dmd.nRows/nCols`) | %VERIFY |
| µm per DMD px at sample | 0.6 assumed (`fov.umPerDmdPx`) | %VERIFY measured |
| dmdToScan affine | `calibration_file` via `run_dmd_scan_calibration.m` | %VERIFY |
