classdef test_generateEnsembles < matlab.unittest.TestCase
    %test_generateEnsembles The design-matrix source of truth must be seeded,
    %   reproducible, and internally consistent (X <-> memberIds), exclude
    %   the patched cell, and respect the size distribution — the Python
    %   pipeline trusts ensembles.mat blindly, so this file is its warranty.

    methods (Test)
        function seed_reproducibility(tc)
            [targets, config] = fixture();
            e1 = sem.protocol.generateEnsembles(targets, config, 99);
            e2 = sem.protocol.generateEnsembles(targets, config, 99);
            tc.verifyEqual(e1.X, e2.X);
            tc.verifyEqual(e1.memberIds, e2.memberIds);
            e3 = sem.protocol.generateEnsembles(targets, config, 100);
            tc.verifyNotEqual(e1.X, e3.X);
        end

        function x_matches_memberIds(tc)
            [targets, config] = fixture();
            ens = sem.protocol.generateEnsembles(targets, config, 7);
            for i = 1:size(ens.X, 1)
                cols = find(ens.X(i, :) > 0);
                if isempty(ens.memberIds{i})
                    tc.verifyEmpty(cols, sprintf('row %d: blank has ON columns', i));
                else
                    tc.verifyEqual(sort(ens.cellIds(cols)), sort(ens.memberIds{i}), ...
                        sprintf('row %d: X columns disagree with memberIds', i));
                end
            end
        end

        function patched_cell_never_a_member(tc)
            [targets, config] = fixture();
            targets.patchedCellId = 3;
            ens = sem.protocol.generateEnsembles(targets, config, 7);
            allMembers = [ens.memberIds{:}];
            tc.verifyFalse(ismember(3, allMembers));
            [~, col3] = ismember(3, ens.cellIds);
            tc.verifyEqual(ens.X(:, col3), zeros(size(ens.X, 1), 1));
        end

        function sizes_and_kinds(tc)
            [targets, config] = fixture();
            config.ensemble.nEnsembles = 30;
            config.ensemble.nBlank = 4;
            config.ensemble.sizeMin = 3;
            config.ensemble.sizeMax = 6;
            ens = sem.protocol.generateEnsembles(targets, config, 5);
            tc.verifyEqual(size(ens.X, 1), 34);
            szs = cellfun(@numel, ens.memberIds(strcmp(ens.kinds, 'ensemble')));
            tc.verifyGreaterThanOrEqual(min(szs), 3);
            tc.verifyLessThanOrEqual(max(szs), 6);
            tc.verifyEqual(nnz(strcmp(ens.kinds, 'blank')), 4);
            blankRows = find(strcmp(ens.kinds, 'blank'));
            tc.verifyEqual(ens.X(blankRows, :), zeros(4, numel(ens.cellIds)));
        end

        function fills_from_levels(tc)
            [targets, config] = fixture();
            ens = sem.protocol.generateEnsembles(targets, config, 5);
            nz = ens.X(ens.X > 0);
            tc.verifyTrue(all(ismember(nz, config.ensemble.fillLevels)));
        end

        function ensemble_seeds_unique(tc)
            [targets, config] = fixture();
            ens = sem.protocol.generateEnsembles(targets, config, 5);
            tc.verifyEqual(numel(unique(ens.ensembleSeed)), numel(ens.ensembleSeed));
        end
    end
end

% --- Local helpers ---

function [targets, config] = fixture()
n = 10;
cells = struct('id', {}, 'scanfieldXY', {}, 'dmdXY', {}, 'layer', {}, ...
    'isOpsinPos', {}, 'score', {}, 'notes', {});
for k = 1:n
    cells(k) = struct('id', k, 'scanfieldXY', [k, k], ...
        'dmdXY', [100 + 20 * k, 200], 'layer', 1, 'isOpsinPos', true, ...
        'score', 1, 'notes', '');
end
targets = struct('version', 1, 'patchedCellId', NaN, 'cells', cells, ...
    'umPerDmdPx', 0.6);
config = struct( ...
    'ensemble', struct('nEnsembles', 20, 'sizeMin', 2, 'sizeMax', 5, ...
        'fillLevels', [0.25, 0.5, 0.75, 1.0], 'nBlank', 3, ...
        'nSingleCell', 0, 'laserVolts', 2.0), ...
    'dmd', struct('spotRadiusPx', 8));
end
