function result = exp_slice_ppsf(configOrPath, sessionName, options)
%exp_slice_ppsf Rigorous PPSF factorial around a patched soma (current clamp).
%   result = sem.experiments.exp_slice_ppsf(configOrPath, sessionName, options)
%
%   Measures direct optogenetic activation of the PATCHED cell as a function
%   of laser power x spot offset from the soma x DMD fill factor, in current
%   clamp (subthreshold depolarization + spike counts). The factorial is
%   config.ppsf: laserVoltsLevels x gaussianGrid2D offsets (dense near the
%   soma) x fillFactors x nReps, seeded shuffle.
%
%   Mock sessions fabricate targets and a ground-truth network (the model's
%   params.ppsfSigmaUm is the lateral PPSF this experiment should recover).
%   Real sessions require options.targetsPath (from the targeting workflow)
%   and options.patchedCellId.
%
%   options (struct, all optional in mock):
%     .targetsPath    targets.mat from sem.targeting (REQUIRED when real)
%     .patchedCellId  id in targets.cells (default: mock picks center cell)
%     .seed           shuffle seed (default 1234)
%     .interactive    operator prompts (default false)
%
%   result: sessionDir, blockResult, trialTable, conditions.

if nargin < 3 || isempty(options)
    options = struct();
end
config = resolveConfig(configOrPath);
seed = sem.util.configField(options, 'seed', 1234);

sessionDir = fullfile(sem.util.configField(config.paths, 'dataDir', 'data'), ...
    char(sessionName));
if ~isfolder(sessionDir)
    mkdir(sessionDir);
end
tfp.io.sessionLog(sessionDir, 'session-start', struct( ...
    'experiment', 'exp_slice_ppsf', 'sessionName', char(sessionName)));

[dmd, daq] = sem.hardware.makeRig(config);
cleanupObj = onCleanup(@() teardownHardware(dmd, daq)); %#ok<NASGU>

[targets, patchedCell] = resolveTargets(config, options, sessionDir, daq);

% --- Build the PPSF factorial as one CC block ----------------------------
pCfg = sem.util.configField(config, 'ppsf', struct());
offsetsUm = tfp.trial.TrialSequence.gaussianGrid2D( ...
    sem.util.configField(pCfg, 'offsetsMaxUm', 60), ...
    sem.util.configField(pCfg, 'nPointsPerHalfAxis', 4), 8);
laserLevels = sem.util.configField(pCfg, 'laserVoltsLevels', [0.5, 1.0, 2.0]);
fillFactors = sem.util.configField(pCfg, 'fillFactors', [0.25, 0.5, 1.0]);
nReps = sem.util.configField(pCfg, 'nReps', 2);
radiusPx = sem.util.configField(pCfg, 'radiusPx', 17);
umPerPx = targets.umPerDmdPx;

conditions = struct('offsetUm', {}, 'distanceUm', {}, 'laserVolts', {}, ...
    'fillFactor', {}, 'repIdx', {});
for rep = 1:nReps
    for iP = 1:numel(laserLevels)
        for iF = 1:numel(fillFactors)
            for iO = 1:size(offsetsUm, 1)
                conditions(end+1) = struct( ...
                    'offsetUm', offsetsUm(iO, :), ...
                    'distanceUm', norm(offsetsUm(iO, :)), ...
                    'laserVolts', laserLevels(iP), ...
                    'fillFactor', fillFactors(iF), ...
                    'repIdx', rep); %#ok<AGROW>
            end
        end
    end
end
rs = RandStream('mt19937ar', 'Seed', seed);
conditions = conditions(randperm(rs, numel(conditions)));

trials = struct('kind', {}, 'ensembleId', {}, 'memberIds', {}, ...
    'centroids', {}, 'fillFractions', {}, 'laserVolts', {}, ...
    'patternSeed', {}, 'extraMeta', {});
for i = 1:numel(conditions)
    c = conditions(i);
    centroid = patchedCell.dmdXY + round(c.offsetUm / umPerPx);
    trials(i) = struct( ...
        'kind',          'direct', ...
        'ensembleId',    NaN, ...
        'memberIds',     patchedCell.id, ...
        'centroids',     centroid, ...
        'fillFractions', c.fillFactor, ...
        'laserVolts',    c.laserVolts, ...
        'patternSeed',   seed + i, ...
        'extraMeta',     c);
end

blockPlan = struct( ...
    'label',       'CC', ...
    'blockId',     1, ...
    'mode',        'IC', ...
    'holdingMv',   0, ...
    'radiusPx',    radiusPx, ...
    'shuffleSeed', seed, ...
    'trials',      trials);

runner = sem.protocol.EpisodicRunner(dmd, daq, config, sessionDir);
blockResult = runner.runBlock(blockPlan, struct( ...
    'interactive', sem.util.configField(options, 'interactive', false)));

% --- Quick-look table ----------------------------------------------------
trialTable = struct('trialIdx', {}, 'distanceUm', {}, 'laserVolts', {}, ...
    'fillFactor', {}, 'peakDepolMv', {}, 'nSpikes', {});
for i = 1:numel(blockResult.trials)
    tr = blockResult.trials{i};
    if ~strcmp(tr.status, 'complete') || ~strcmp(tr.metadata.ephys.kind, 'direct')
        continue
    end
    s = sem.analysis.quickTrialSummary(tr, config);
    c = tr.metadata.extra;
    trialTable(end+1) = struct( ...
        'trialIdx', tr.trialIdx, 'distanceUm', c.distanceUm, ...
        'laserVolts', c.laserVolts, 'fillFactor', c.fillFactor, ...
        'peakDepolMv', s.peakAbsResponse, 'nSpikes', s.nSpikes); %#ok<AGROW>
end

tfp.io.sessionLog(sessionDir, 'session-end', struct( ...
    'nTrials', numel(blockResult.trials), 'nFailed', blockResult.nFailed));

result = struct();
result.sessionDir = sessionDir;
result.blockResult = blockResult;
result.trialTable = trialTable;
result.conditions = conditions;
end

% =========================================================================

function config = resolveConfig(configOrPath)
if isstruct(configOrPath)
    config = configOrPath;
else
    config = tfp.io.loadConfig(configOrPath);
end
end

function [targets, patchedCell] = resolveTargets(config, options, sessionDir, daq)
if strcmpi(config.hardwareKind, 'mock')
    targets = sem.targeting.mockTargets(config);
else
    targetsPath = sem.util.configField(options, 'targetsPath', '');
    if isempty(targetsPath)
        error('sem:experiments:exp_slice_ppsf:noTargets', ...
            'Real sessions require options.targetsPath (see scripts/run_targeting.m).');
    end
    targets = sem.io.loadTargets(targetsPath);
end

patchedCellId = sem.util.configField(options, 'patchedCellId', targets.patchedCellId);
if isnan(patchedCellId)
    if strcmpi(config.hardwareKind, 'mock')
        % Default: the cell closest to the DMD-coordinate centroid of all cells.
        xy = reshape([targets.cells.dmdXY], 2, []).';
        d = vecnorm(xy - mean(xy, 1), 2, 2);
        [~, k] = min(d);
        patchedCellId = targets.cells(k).id;
    else
        error('sem:experiments:exp_slice_ppsf:noPatchedCell', ...
            'Set options.patchedCellId (which target you patched).');
    end
end
targets.patchedCellId = patchedCellId;
ids = [targets.cells.id];
patchedCell = targets.cells(ids == patchedCellId);
if isempty(patchedCell)
    error('sem:experiments:exp_slice_ppsf:badPatchedCell', ...
        'patchedCellId %g is not in targets.', patchedCellId);
end
sem.io.saveTargets(targets, sessionDir);

if strcmpi(config.hardwareKind, 'mock')
    model = sem.sim.makeGroundTruthNetwork(config, targets);
    daq.attachNetworkModel(model);
    sem.io.saveGroundTruth(model.exportGroundTruth(), sessionDir);
end
end

function teardownHardware(dmd, daq)
try, dmd.cleanup(); catch, end %#ok<CTCH>
try, daq.cleanup(); catch, end %#ok<CTCH>
end
