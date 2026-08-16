function ens = generateEnsembles(targets, config, seed)
%generateEnsembles Draw the seeded random-ensemble set and its design matrix.
%   ens = sem.protocol.generateEnsembles(targets, config, seed)
%
%   THE DESIGN-MATRIX SOURCE OF TRUTH. The Python analysis reads ensembles.mat
%   and never reconstructs membership from DMD patterns. Membership, per-cell
%   fill fractions (the per-cell power knob), and per-ensemble pattern seeds
%   are all drawn here from one RandStream so the same (targets, config, seed)
%   always reproduces the identical set.
%
%   Candidate cells: opsin+ cells excluding the patched cell (stimulating
%   the recorded soma directly would confound the synaptic measurement).
%
%   config.ensemble keys: nEnsembles, sizeMin, sizeMax, fillLevels, nBlank,
%   nSingleCell, laserVolts. config.dmd.spotRadiusPx sets radiusPx.
%
%   ens (versioned struct):
%     .version, .seed, .cfgSnapshot
%     .cellIds       1 x nCells      (ALL target cells; columns of X)
%     .candidateIds  1 x nCand       (cells eligible for membership)
%     .X             nTrials x nCells double, X(i,k) = fill fraction of cell
%                    cellIds(k) in trial i (0 = not a member)
%     .memberIds     {nTrials x 1}   member cell ids per trial
%     .kinds         {nTrials x 1}   'ensemble' | 'single' | 'blank'
%     .ensembleSeed  nTrials x 1     per-trial pattern RNG seed (rebuild
%                    patterns exactly via fillFactorEnsemble; patterns are
%                    never stored — GBs — only reproduced)
%     .radiusPx, .laserVolts

eCfg = sem.util.configField(config, 'ensemble', struct());
nEnsembles = sem.util.configField(eCfg, 'nEnsembles', 100);
sizeMin = sem.util.configField(eCfg, 'sizeMin', 5);
sizeMax = sem.util.configField(eCfg, 'sizeMax', 15);
fillLevels = sem.util.configField(eCfg, 'fillLevels', [0.25, 0.5, 0.75, 1.0]);
nBlank = sem.util.configField(eCfg, 'nBlank', 10);
nSingleCell = sem.util.configField(eCfg, 'nSingleCell', 0);
laserVolts = sem.util.configField(eCfg, 'laserVolts', 2.0);
radiusPx = sem.util.configField(sem.util.configField(config, 'dmd', struct()), ...
    'spotRadiusPx', 17);

cellIds = [targets.cells.id];
nCells = numel(cellIds);
isCandidate = [targets.cells.isOpsinPos];
if ~isnan(targets.patchedCellId)
    isCandidate = isCandidate & cellIds ~= targets.patchedCellId;
end
candidateIds = cellIds(isCandidate);
nCand = numel(candidateIds);
if nCand < max(1, sizeMin)
    error('sem:protocol:generateEnsembles:tooFewCandidates', ...
        'Only %d candidate cells for ensembles of size >= %d.', nCand, sizeMin);
end
sizeMaxEff = min(sizeMax, nCand);

rs = RandStream('mt19937ar', 'Seed', seed);
nTrials = nEnsembles + nSingleCell + nBlank;

X = zeros(nTrials, nCells);
memberIds = cell(nTrials, 1);
kinds = cell(nTrials, 1);

row = 0;
for i = 1:nEnsembles
    row = row + 1;
    sz = randi(rs, [sizeMin, sizeMaxEff]);
    pick = candidateIds(randperm(rs, nCand, sz));
    fills = fillLevels(randi(rs, numel(fillLevels), 1, sz));
    [~, cols] = ismember(pick, cellIds);
    X(row, cols) = fills;
    memberIds{row} = pick;
    kinds{row} = 'ensemble';
end
for i = 1:nSingleCell
    row = row + 1;
    pick = candidateIds(randi(rs, nCand));
    [~, col] = ismember(pick, cellIds);
    X(row, col) = 1.0;
    memberIds{row} = pick;
    kinds{row} = 'single';
end
for i = 1:nBlank
    row = row + 1;
    memberIds{row} = [];
    kinds{row} = 'blank';
end

ens = struct();
ens.version = 1;
ens.seed = seed;
ens.cfgSnapshot = eCfg;
ens.cellIds = cellIds;
ens.candidateIds = candidateIds;
ens.X = X;
ens.memberIds = memberIds;
ens.kinds = kinds;
ens.ensembleSeed = seed + (1:nTrials)';
ens.radiusPx = radiusPx;
ens.laserVolts = laserVolts;
end
