function result = exp_ensemble_ei(configOrPath, sessionName, options)
%exp_ensemble_ei Random-ensemble E/I mapping session (multi-block, replayed).
%   result = sem.experiments.exp_ensemble_ei(configOrPath, sessionName, options)
%
%   The core mapping experiment: draws a seeded set of random ensembles of
%   opsin+ somata (membership + per-cell fill-factor power; ensembles.mat is
%   the design-matrix source of truth) and presents the IDENTICAL set in
%   every clamp block of config.ensemble.blocks — CC (Vm + spikes), VC at
%   -70 mV (evoked excitation), VC at +10 mV (evoked inhibition) — so E and
%   I are pairable per ensembleId. Holding switches are software-driven;
%   VC<->IC mode switches prompt the operator between blocks.
%
%   Mock sessions fabricate targets + a ground-truth network and save
%   ground_truth.mat — the Python roundtrip (analysis/tests/
%   test_mock_roundtrip.py) must recover the true weights from the session
%   this function writes.
%
%   options (struct, all optional in mock):
%     .targetsPath    targets.mat (REQUIRED when real)
%     .patchedCellId  id in targets.cells (default: mock picks center cell)
%     .seed           ensemble-draw seed (default 1234)
%     .interactive    operator prompts between blocks (default false)
%     .blocks         cellstr override of config.ensemble.blocks
%
%   result: sessionDir, ensemblesPath, blockResults (one per block),
%   ensembleIdsPerBlock (replay-identity check input).

if nargin < 3 || isempty(options)
    options = struct();
end
config = resolveConfig(configOrPath);
seed = sem.util.configField(options, 'seed', 1234);
if isfield(options, 'blocks')
    config.ensemble.blocks = options.blocks;
end

sessionDir = fullfile(sem.util.configField(config.paths, 'dataDir', 'data'), ...
    char(sessionName));
if ~isfolder(sessionDir)
    mkdir(sessionDir);
end
tfp.io.sessionLog(sessionDir, 'session-start', struct( ...
    'experiment', 'exp_ensemble_ei', 'sessionName', char(sessionName), ...
    'seed', seed));

[dmd, daq] = sem.hardware.makeRig(config);
cleanupObj = onCleanup(@() teardownHardware(dmd, daq)); %#ok<NASGU>

targets = resolveTargets(config, options, sessionDir, daq);

% --- Ensemble set + per-block plans (identical set, reshuffled order) ----
ens = sem.protocol.generateEnsembles(targets, config, seed);
ensemblesPath = sem.io.saveEnsembles(ens, sessionDir);
blockPlans = sem.protocol.planBlocks(ens, targets, config);

saveConfigSnapshot(config, configOrPath, sessionDir);

runner = sem.protocol.EpisodicRunner(dmd, daq, config, sessionDir);
opts = struct('interactive', sem.util.configField(options, 'interactive', false));

blockResults = cell(1, numel(blockPlans));
ensembleIdsPerBlock = cell(1, numel(blockPlans));
for b = 1:numel(blockPlans)
    blockResults{b} = runner.runBlock(blockPlans(b), opts);
    ensembleIdsPerBlock{b} = sort([blockPlans(b).trials.ensembleId]);
end

% Replay identity: every block must have presented the same ensemble set.
for b = 2:numel(blockPlans)
    if ~isequal(ensembleIdsPerBlock{1}, ensembleIdsPerBlock{b})
        error('sem:experiments:exp_ensemble_ei:replayMismatch', ...
            'Block %d presented a different ensemble set than block 1.', b);
    end
end

nFailedTotal = sum(cellfun(@(r) r.nFailed, blockResults));
tfp.io.sessionLog(sessionDir, 'session-end', struct( ...
    'nBlocks', numel(blockPlans), 'nFailed', nFailedTotal));

result = struct();
result.sessionDir = sessionDir;
result.ensemblesPath = ensemblesPath;
result.blockResults = {blockResults{:}}; %#ok<CCAT1>
result.ensembleIdsPerBlock = ensembleIdsPerBlock;
end

% =========================================================================

function config = resolveConfig(configOrPath)
if isstruct(configOrPath)
    config = configOrPath;
else
    config = tfp.io.loadConfig(configOrPath);
end
end

function targets = resolveTargets(config, options, sessionDir, daq)
if strcmpi(config.hardwareKind, 'mock')
    targets = sem.targeting.mockTargets(config);
else
    targetsPath = sem.util.configField(options, 'targetsPath', '');
    if isempty(targetsPath)
        error('sem:experiments:exp_ensemble_ei:noTargets', ...
            'Real sessions require options.targetsPath (see scripts/run_targeting.m).');
    end
    targets = sem.io.loadTargets(targetsPath);
end

patchedCellId = sem.util.configField(options, 'patchedCellId', targets.patchedCellId);
if isnan(patchedCellId)
    if strcmpi(config.hardwareKind, 'mock')
        xy = reshape([targets.cells.dmdXY], 2, []).';
        d = vecnorm(xy - mean(xy, 1), 2, 2);
        [~, k] = min(d);
        patchedCellId = targets.cells(k).id;
    else
        error('sem:experiments:exp_ensemble_ei:noPatchedCell', ...
            'Set options.patchedCellId (which target you patched).');
    end
end
targets.patchedCellId = patchedCellId;
sem.io.saveTargets(targets, sessionDir);

if strcmpi(config.hardwareKind, 'mock')
    model = sem.sim.makeGroundTruthNetwork(config, targets);
    daq.attachNetworkModel(model);
    sem.io.saveGroundTruth(model.exportGroundTruth(), sessionDir);
end
end

function saveConfigSnapshot(config, configOrPath, sessionDir)
snapshotMat = fullfile(sessionDir, 'config_snapshot.mat');
save(snapshotMat, 'config', '-v7.3');
if ~isstruct(configOrPath) && isfile(char(configOrPath))
    copyfile(char(configOrPath), fullfile(sessionDir, 'config_snapshot.yaml'));
end
end

function teardownHardware(dmd, daq)
try, dmd.cleanup(); catch, end %#ok<CTCH>
try, daq.cleanup(); catch, end %#ok<CTCH>
end
