# On-disk data schema

Everything is `.mat` v7.3 (HDF5), readable from Python via
`analysis/src/slice_ephys_analysis/io_mat.py`. Rule: **no MATLAB `string`,
`datetime`, or `table` objects in any field Python needs** — those save as
opaque blobs; the loader returns them as `None`. Use plain doubles / char /
struct / cell.

## Session directory

```
data/<sessionName>/                       (exp_ensemble_ei; ppsf is one block)
├── config_snapshot.mat  (+ .yaml copy)   config struct as run
├── targets.mat                            the cell list (below)
├── ensembles.mat                          THE design-matrix source of truth
├── ground_truth.mat                       mock sessions only (roundtrip contract)
├── log.txt                                tfp.io.sessionLog TSV
└── block_<k>_<label>/                     one per clamp block (vc70, vc10, cc)
    ├── session.mat                        full stopContinuousSession record + blockMeta
    └── trials/trial_%04d_{meta,raw}.mat   tfp.io.saveTrial schema v2
```

## targets.mat (`targets`)

`version` 1 · `createdDatetime` · `refImagePath` · `calibrationPath` ·
`umPerDmdPx` · `patchedCellId` (NaN until set) ·
`cells(k)`: `id`, `scanfieldXY` [x y], `dmdXY` [col row, 1-based],
`layer`, `isOpsinPos`, `score`, `notes`.

## ensembles.mat (`ens`) — Python never reconstructs membership from patterns

- `version` 1, `seed`, `cfgSnapshot`
- `cellIds` 1×nCells — the columns of X (ALL target cells)
- `candidateIds` — cells eligible for membership (opsin+, not patched)
- `X` nTrials×nCells double — `X(i,k)` = fill fraction of cell `cellIds(k)`
  in trial i (0 = not a member). **The regression design matrix.**
- `memberIds` {nTrials×1}, `kinds` {nTrials×1} ('ensemble'|'single'|'blank')
- `ensembleSeed` nTrials×1 — pattern RNG seed per trial;
  `fillFactorEnsemble(..., struct('rngSeed', ensembleSeed(i)))` reproduces
  the exact DMD frame (patterns are never stored — GBs)
- `radiusPx`, `laserVolts`

## ground_truth.mat (`gt`, mock only)

`seed`, `cellIds`, `opsinGain`, `W_E_pC` (charge/spike), `releaseProb`,
`cI`, **`W_E_eff`**, **`W_I_eff`** (expected pC per unit fill at reference
laser volts — the quantities the regression estimates), `params`.

## Trial files (tfp.io.saveTrial schema v2)

`trial_%04d_meta.mat` (`meta`): `trialIdx`, `status`, `targetSpec` (pattern
stripped), `powerMw` (= laser VOLTS until a power cal exists), `timingSpec`,
`metadata` (below), `responseSummary`, `fileRef`, the seven sync fields
(`t_onset_daq_samples`, `t_offset_daq_samples`,
`daq_master_sample_rate_hz`, ...).

`trial_%04d_raw.mat` (`raw`): `aiData` — the sliced AI snippet, nSamples ×
nAI, **DAQ VOLTS** (preS before onset .. postS after offset).

### metadata.ephys (schemaVersion 1) — rides in every meta file

| Field | Meaning |
|---|---|
| `clampMode` | 'VC' \| 'IC' |
| `holdingMv` | software-commanded holding (`holdingSource` 'software'; Commander assumed 0) |
| `blockLabel` / `blockId` | 'CC' \| 'VC-70' \| 'VC+10' |
| `gains` | Units gain snapshot — the ONLY source for volt→cell conversion |
| `aiChannelMap.scaledOutput` | 1-based column of aiData holding the 700B scaled output |
| `scaledUnits` | 'pA' (VC) \| 'mV' (IC) after conversion |
| `stimOnsetSampleInSnippet` | 1-based stim-onset row within aiData |
| `stimDurS`, `laserVolts`, `laserPowerMwEst`, `powerNote` | stimulus provenance |
| `ensembleId` | 1-based row into ens.X — the replay/join key (NaN for sealTest) |
| `kind` | 'ensemble' \| 'single' \| 'blank' \| 'direct' (PPSF) \| 'sealTest' |

`metadata.itiS` and `metadata.extra` (PPSF factorial coords: `offsetUm`,
`distanceUm`, `laserVolts`, `fillFactor`, `repIdx`) ride alongside.

## block session.mat

`sessionData`: verbatim `stopContinuousSession` result (`aiData` full-block
record, `nSamplesTotal`, `sampleRate`, `lineNames`). `blockMeta`: label,
mode, holdingMv, shuffleSeed, gains, sampleRate. This is the uncut record —
per-trial snippets can always be re-cut from it.
