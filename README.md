# slice-ephys-mapping

Slice patch-clamp experiments driven by the lab's DMD temporal-focusing
photostimulation system (the sibling
[DMD-control-flow-software](../DMD-control-flow-software) repo, consumed as
a read-only MATLAB library):

1. **Rigorous PPSF** (`sem.experiments.exp_slice_ppsf`) — subthreshold
   depolarization + spiking of a patched cell vs laser power × spot offset ×
   DMD fill factor, current clamp.
2. **Random-ensemble E/I mapping** (`sem.experiments.exp_ensemble_ei`) —
   thousands of seeded random ensembles of opsin+ somata; the identical
   ensemble set replayed across CC / VC −70 mV (E) / VC +10 mV (I) blocks
   with software-controlled holding; Python ridge regression recovers
   per-cell weights onto the patched target; E/I coupling per ensemble.

## Status

Phase A complete (2026-08-16): mock-only end-to-end on macOS. 61/61 MATLAB
tests, 29/29 Python tests including the **mock roundtrip** — a simulated
600-ensemble session from known weights, recovered at r = 0.99 (E) / 0.91
(I) with all zero-weight/opsin− cells under the permutation null
([figures/roundtrip](figures/roundtrip/png/mock_roundtrip_validation.png)).
Phase B (rig bringup: wiring, power cal, DMD→scan affine) not started — all
hardware assignments are %VERIFY placeholders.

## How to run

```bash
# MATLAB suite (also asserts the tfp API tripwire)
/Applications/MATLAB_R2023a.app/bin/matlab -nodisplay -batch "runtests"

# Python suite
cd analysis && .venv/bin/python -m pytest

# Full mock roundtrip (few minutes)
matlab -nodisplay -batch "run(fullfile('scripts','run_mock_session.m'))"
cd analysis && .venv/bin/python -m pytest tests/test_mock_roundtrip.py -v
.venv/bin/python -m slice_ephys_analysis.figures     # validation figure
```

First-time Python setup: `cd analysis && python3 -m venv .venv &&
.venv/bin/pip install -e ".[dev]"`.

The DMD repo is found at `~/code/DMD-control-flow-software` by default;
override with `configs/dmd_repo_path_local.m` (see the `.example`).

## Repo layout

- `src/+sem/` — MATLAB control package (hardware mocks, ground-truth sim,
  targeting, protocols, experiments, io, analysis, util)
- `analysis/` — Python package `slice_ephys_analysis` (loaders, units, PSC,
  regression, E/I coupling, validation, figures)
- `configs/` — `mock.yaml` (dev) and `slice_rig.yaml` (rig, %VERIFY)
- `scripts/` — mock roundtrip + Phase B bringup (`verify_wiring`,
  `run_power_calibration`, `run_dmd_scan_calibration`, `run_targeting`)
- `docs/` — [DEPENDENCIES](docs/DEPENDENCIES.md) (tfp contract),
  [WIRING](docs/WIRING.md), [DATA_SCHEMA](docs/DATA_SCHEMA.md),
  [USER_GUIDE](docs/USER_GUIDE.md) (+ PDF)
- `tests/` — MATLAB suite; `figures/` — tracked figure artifacts;
  `data/` — session outputs (gitignored)

## More

[CLAUDE.md](CLAUDE.md) (conventions + design decisions) →
[ARCHITECTURE.md](ARCHITECTURE.md) → [docs/USER_GUIDE.md](docs/USER_GUIDE.md).
