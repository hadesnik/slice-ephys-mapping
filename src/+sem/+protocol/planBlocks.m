function blockPlans = planBlocks(ens, targets, config)
%planBlocks Expand the ensemble set into per-block trial plans.
%   blockPlans = sem.protocol.planBlocks(ens, targets, config)
%
%   One block per entry of config.ensemble.blocks ('CC' | 'VC-70' | 'VC+10').
%   EVERY block presents the IDENTICAL ensemble set (same ensembleIds) —
%   that is what makes E and I pairable per ensemble across holding
%   potentials — with an independent seeded reshuffle of presentation order
%   per block. Replay identity is by ensembleId (the row into ens.X), which
%   rides in every trial's metadata.
%
%   Block labels map to clamp state (holdings from config.ephys):
%     'CC'     -> mode IC, command 0 pA        (subthreshold Vm + spikes)
%     'VC-70'  -> mode VC, holdingVcEMv (-70)  (evoked excitation)
%     'VC+10'  -> mode VC, holdingVcIMv (+10)  (evoked inhibition)
%
%   Each blockPlan: label, blockId, mode, holdingMv, radiusPx, shuffleSeed,
%   trials(i): struct with kind, ensembleId, memberIds, centroids (Mx2 DMD
%   [col row]), fillFractions (Mx1), laserVolts, patternSeed, extraMeta.

labels = sem.util.configField(sem.util.configField(config, 'ensemble', struct()), ...
    'blocks', {{'VC-70', 'VC+10'}});
if ~iscell(labels)
    labels = cellstr(labels);
end
eCfg = sem.util.configField(config, 'ephys', struct());
holdE = sem.util.configField(eCfg, 'holdingVcEMv', -70);
holdI = sem.util.configField(eCfg, 'holdingVcIMv', 10);

cellIds = [targets.cells.id];
dmdXYAll = reshape([targets.cells.dmdXY], 2, []).';

nTrials = size(ens.X, 1);
blockPlans = struct('label', {}, 'blockId', {}, 'mode', {}, 'holdingMv', {}, ...
    'radiusPx', {}, 'shuffleSeed', {}, 'trials', {});

for b = 1:numel(labels)
    label = char(labels{b});
    switch label
        case 'CC'
            mode = 'IC'; holdingMv = 0;
        case 'VC-70'
            mode = 'VC'; holdingMv = holdE;
        case 'VC+10'
            mode = 'VC'; holdingMv = holdI;
        otherwise
            error('sem:protocol:planBlocks:badLabel', ...
                'Unknown block label ''%s'' (want CC | VC-70 | VC+10).', label);
    end

    % Keep within RandStream's [0, 2^32) seed range for any ens.seed.
    shuffleSeed = mod(ens.seed * 7919 + b, 2^31);
    rs = RandStream('mt19937ar', 'Seed', shuffleSeed);
    order = randperm(rs, nTrials);

    trials = struct('kind', {}, 'ensembleId', {}, 'memberIds', {}, ...
        'centroids', {}, 'fillFractions', {}, 'laserVolts', {}, ...
        'patternSeed', {}, 'extraMeta', {});
    for i = 1:nTrials
        row = order(i);
        members = ens.memberIds{row};
        if isempty(members)
            centroids = zeros(0, 2);
            fills = zeros(0, 1);
        else
            [~, cellRows] = ismember(members, cellIds);
            centroids = dmdXYAll(cellRows, :);
            [~, cols] = ismember(members, ens.cellIds);
            fills = ens.X(row, cols)';
        end
        trials(i) = struct( ...
            'kind',          ens.kinds{row}, ...
            'ensembleId',    row, ...
            'memberIds',     members, ...
            'centroids',     centroids, ...
            'fillFractions', fills, ...
            'laserVolts',    ens.laserVolts, ...
            'patternSeed',   ens.ensembleSeed(row), ...
            'extraMeta',     struct());
    end

    blockPlans(b) = struct( ...
        'label',       label, ...
        'blockId',     b, ...
        'mode',        mode, ...
        'holdingMv',   holdingMv, ...
        'radiusPx',    ens.radiusPx, ...
        'shuffleSeed', shuffleSeed, ...
        'trials',      trials);
end
end
