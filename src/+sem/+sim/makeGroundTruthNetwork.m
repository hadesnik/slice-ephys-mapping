function model = makeGroundTruthNetwork(config, targets)
%makeGroundTruthNetwork Build a seeded SliceNetworkModel from config + targets.
%   model = sem.sim.makeGroundTruthNetwork(config, targets)
%
%   config: full config struct (uses config.groundTruth scalar knobs,
%   config.ephys gains, config.ensemble.laserVolts as the reference laser
%   voltage). targets: targets struct from sem.targeting (cells aligned 1:1
%   with the model — targets.cells(k).id becomes model.cellIds(k)).
%
%   All draws use a local RandStream seeded from config.groundTruth.seed so
%   the same config + targets always produce the same network. The model's
%   own synthesis stream is seeded from the same value.

gtCfg = sem.util.configField(config, 'groundTruth', struct());
seed  = sem.util.configField(gtCfg, 'seed', 42);
rs    = RandStream('mt19937ar', 'Seed', seed);

nCells = numel(targets.cells);
if nCells == 0
    error('sem:sim:makeGroundTruthNetwork:noCells', ...
        'targets must contain at least one cell.');
end
cellIds = [targets.cells.id];

opsinNegFraction = sem.util.configField(gtCfg, 'opsinNegFraction', 0.15);
connectedFraction = sem.util.configField(gtCfg, 'connectedFraction', 0.3);
wEMeanPc = sem.util.configField(gtCfg, 'wEMeanPc', 2.0);
releaseProbCfg = sem.util.configField(gtCfg, 'releaseProb', 0.85);
opsinGainMean = sem.util.configField(gtCfg, 'opsinGainMean', 2.5);
iCouplingSigma = sem.util.configField(gtCfg, 'iCouplingSigma', 0.5);

% Opsin expression: most cells opsin+, gains lognormal around the mean;
% opsin- cells have exactly zero optical drive (a key roundtrip assertion:
% their recovered weights must sit at the noise floor).
opsinGain = opsinGainMean * exp(0.3 * randn(rs, nCells, 1));
nNeg = round(opsinNegFraction * nCells);
negIdx = randperm(rs, nCells, nNeg);
opsinGain(negIdx) = 0;

% Sparse lognormal excitatory weights onto the patched cell.
wE = zeros(nCells, 1);
nConn = max(1, round(connectedFraction * nCells));
connIdx = randperm(rs, nCells, nConn);
wE(connIdx) = wEMeanPc * exp(0.5 * randn(rs, nConn, 1));

releaseProb = repmat(releaseProbCfg, nCells, 1);

% Per-cell coupling into the polysynaptic inhibitory pathway (all positive;
% every spiking cell recruits some inhibition, with cell-to-cell spread).
cI = abs(1 + iCouplingSigma * randn(rs, nCells, 1));

params = struct();
params.laserVoltsRef     = sem.util.configField( ...
    sem.util.configField(config, 'ensemble', struct()), 'laserVolts', 2.0);
params.maxSpikesPerPulse = sem.util.configField(gtCfg, 'maxSpikesPerPulse', 3);
params.spikeLatencyMs    = sem.util.configField(gtCfg, 'spikeLatencyMs', 2.5);
params.spikeJitterMs     = sem.util.configField(gtCfg, 'spikeJitterMs', 1.0);
params.monoLatencyMs     = sem.util.configField(gtCfg, 'monoLatencyMs', 2.0);
params.diLatencyMs       = sem.util.configField(gtCfg, 'diLatencyMs', 5.0);
params.diJitterMs        = sem.util.configField(gtCfg, 'diJitterMs', 1.5);
params.wIGainPc          = sem.util.configField(gtCfg, 'wIGainPc', 0.6);
params.epscTauRMs        = 0.5;
params.epscTauDMs        = 3.0;
params.ipscTauRMs        = 1.0;
params.ipscTauDMs        = 10.0;
params.eeMv              = 0;
params.eiMv              = -70;
params.rsMohm            = sem.util.configField(gtCfg, 'rsMohm', 12);
params.rinMohm           = sem.util.configField(gtCfg, 'rinMohm', 150);
params.cmPf              = sem.util.configField(gtCfg, 'cmPf', 120);
params.vrestMv           = sem.util.configField(gtCfg, 'vrestMv', -65);
params.spikeThresholdMv  = -45;
params.apAmplitudeMv     = 85;
params.noiseRmsPa        = sem.util.configField(gtCfg, 'noiseRmsPa', 4);
params.noiseRmsMv        = sem.util.configField(gtCfg, 'noiseRmsMv', 0.4);
% Spatial + direct-photocurrent ground truth (what exp_slice_ppsf measures).
params.ppsfSigmaUm       = sem.util.configField(gtCfg, 'ppsfSigmaUm', 12);
params.directPeakPa      = sem.util.configField(gtCfg, 'directPeakPa', 400);
params.opsinGainMean     = opsinGainMean;
params.umPerDmdPx        = sem.util.configField( ...
    sem.util.configField(config, 'fov', struct()), 'umPerDmdPx', 0.6);

spec = struct();
spec.nCells      = nCells;
spec.cellIds     = cellIds;
spec.dmdXY       = reshape([targets.cells.dmdXY], 2, []).';
spec.opsinGain   = opsinGain;
spec.wE          = wE;
spec.releaseProb = releaseProb;
spec.cI          = cI;
spec.params      = params;
spec.gain        = sem.util.Units.gainFromConfig( ...
    sem.util.configField(config, 'ephys', struct()));
spec.seed        = seed;

model = sem.sim.SliceNetworkModel(spec);
end
