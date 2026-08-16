classdef test_planBlocks < matlab.unittest.TestCase
    %test_planBlocks The replay contract: every block presents the identical
    %   ensembleId set (E and I pair by ensembleId across holding blocks),
    %   with an independent seeded reshuffle per block, and correct clamp
    %   state per label.

    methods (Test)
        function identical_sets_reshuffled_order(tc)
            [ens, targets, config] = fixture();
            plans = sem.protocol.planBlocks(ens, targets, config);
            tc.verifyEqual(numel(plans), 3);
            ids1 = [plans(1).trials.ensembleId];
            ids2 = [plans(2).trials.ensembleId];
            ids3 = [plans(3).trials.ensembleId];
            tc.verifyEqual(sort(ids1), sort(ids2));
            tc.verifyEqual(sort(ids1), sort(ids3));
            tc.verifyNotEqual(ids1, ids2);   % order independently reshuffled
        end

        function clamp_state_per_label(tc)
            [ens, targets, config] = fixture();
            plans = sem.protocol.planBlocks(ens, targets, config);
            tc.verifyEqual(plans(1).label, 'CC');
            tc.verifyEqual(plans(1).mode, 'IC');
            tc.verifyEqual(plans(2).label, 'VC-70');
            tc.verifyEqual(plans(2).mode, 'VC');
            tc.verifyEqual(plans(2).holdingMv, -70);
            tc.verifyEqual(plans(3).label, 'VC+10');
            tc.verifyEqual(plans(3).holdingMv, 10);
        end

        function trials_carry_pattern_ingredients(tc)
            [ens, targets, config] = fixture();
            plans = sem.protocol.planBlocks(ens, targets, config);
            t = plans(1).trials;
            for i = 1:numel(t)
                if strcmp(t(i).kind, 'blank')
                    tc.verifyEmpty(t(i).centroids);
                else
                    tc.verifyEqual(size(t(i).centroids, 1), numel(t(i).memberIds));
                    tc.verifyEqual(numel(t(i).fillFractions), numel(t(i).memberIds));
                    row = t(i).ensembleId;
                    [~, cols] = ismember(t(i).memberIds, ens.cellIds);
                    tc.verifyEqual(t(i).fillFractions(:).', ens.X(row, cols));
                end
                tc.verifyEqual(t(i).patternSeed, ens.ensembleSeed(t(i).ensembleId));
            end
        end

        function bad_label_throws(tc)
            [ens, targets, config] = fixture();
            config.ensemble.blocks = {'VC-40'};
            tc.verifyError(@() sem.protocol.planBlocks(ens, targets, config), ...
                'sem:protocol:planBlocks:badLabel');
        end
    end
end

% --- Local helpers ---

function [ens, targets, config] = fixture()
n = 8;
cells = struct('id', {}, 'scanfieldXY', {}, 'dmdXY', {}, 'layer', {}, ...
    'isOpsinPos', {}, 'score', {}, 'notes', {});
for k = 1:n
    cells(k) = struct('id', k, 'scanfieldXY', [k, k], ...
        'dmdXY', [100 + 20 * k, 200], 'layer', 1, 'isOpsinPos', true, ...
        'score', 1, 'notes', '');
end
targets = struct('version', 1, 'patchedCellId', 8, 'cells', cells, ...
    'umPerDmdPx', 0.6);
config = struct( ...
    'ensemble', struct('nEnsembles', 15, 'sizeMin', 2, 'sizeMax', 4, ...
        'fillLevels', [0.5, 1.0], 'nBlank', 2, 'nSingleCell', 0, ...
        'laserVolts', 2.0, 'blocks', {{'CC', 'VC-70', 'VC+10'}}), ...
    'ephys', struct('holdingVcEMv', -70, 'holdingVcIMv', 10), ...
    'dmd', struct('spotRadiusPx', 8));
ens = sem.protocol.generateEnsembles(targets, config, 31);
end
