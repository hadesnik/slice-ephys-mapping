classdef test_targets_io < matlab.unittest.TestCase
    %test_targets_io Targets pipeline: fabrication, segmentation import,
    %   affine mapping into DMD coords, and .mat round-trips — the file
    %   formats the Python loader and Phase B rig sessions both consume.

    properties
        TmpDir
    end

    methods (TestMethodSetup)
        function makeTmp(tc)
            tc.TmpDir = tempname();
            mkdir(tc.TmpDir);
        end
    end

    methods (TestMethodTeardown)
        function rmTmp(tc)
            if isfolder(tc.TmpDir)
                rmdir(tc.TmpDir, 's');
            end
        end
    end

    methods (Test)
        function mock_targets_shape(tc)
            config = mockConfig();
            targets = sem.targeting.mockTargets(config);
            tc.verifyEqual(numel(targets.cells), 12);
            xy = reshape([targets.cells.dmdXY], 2, []).';
            tc.verifyTrue(all(xy(:, 1) >= 1 & xy(:, 1) <= 1280));
            tc.verifyTrue(all(xy(:, 2) >= 1 & xy(:, 2) <= 800));
            tc.verifyTrue(all(~isnan([targets.cells.layer])));
        end

        function targets_roundtrip(tc)
            config = mockConfig();
            targets = sem.targeting.mockTargets(config);
            targets.patchedCellId = 4;
            p = sem.io.saveTargets(targets, tc.TmpDir);
            loaded = sem.io.loadTargets(p);
            tc.verifyEqual(loaded.patchedCellId, 4);
            tc.verifyEqual([loaded.cells.id], [targets.cells.id]);
            tc.verifyEqual(reshape([loaded.cells.dmdXY], 2, []).', ...
                reshape([targets.cells.dmdXY], 2, []).');
        end

        function import_from_array_and_files(tc)
            c = [10, 20; 30, 40; 50, 60];
            seg = sem.targeting.importSegmentation(c);
            tc.verifyEqual(seg.centroids, c);

            matPath = fullfile(tc.TmpDir, 'seg.mat');
            centroids = c; %#ok<NASGU>
            save(matPath, 'centroids');
            seg2 = sem.targeting.importSegmentation(matPath);
            tc.verifyEqual(seg2.centroids, c);

            csvPath = fullfile(tc.TmpDir, 'seg.csv');
            writematrix(c, csvPath);
            seg3 = sem.targeting.importSegmentation(csvPath);
            tc.verifyEqual(seg3.centroids, c);
        end

        function import_rejects_garbage(tc)
            tc.verifyError(@() sem.targeting.importSegmentation(zeros(0, 2)), ...
                'sem:targeting:importSegmentation:badCentroids');
            tc.verifyError(@() sem.targeting.importSegmentation('/nonexistent.mat'), ...
                'sem:targeting:importSegmentation:fileNotFound');
        end

        function buildTargets_inverts_affine(tc)
            % Pure-translation affine: DMD -> scanfield is +[100; 50], so
            % scanfield centroids map back by the exact inverse.
            A = [1, 0, 100; 0, 1, 50; 0, 0, 1];
            calibration = struct('dmdToScan_affine', A);
            config = mockConfig();
            seg = struct('centroids', [400, 350; 500, 450], 'score', [1; 1]);
            targets = sem.targeting.buildTargets(seg, calibration, config);
            tc.verifyEqual(numel(targets.cells), 2);
            tc.verifyEqual(targets.cells(1).dmdXY, [300, 300]);
            tc.verifyEqual(targets.cells(2).dmdXY, [400, 400]);
        end

        function buildTargets_drops_out_of_bounds(tc)
            A = eye(3);
            calibration = struct('dmdToScan_affine', A);
            config = mockConfig();
            seg = struct('centroids', [400, 350; 5000, 5000], 'score', [1; 1]);
            tc.verifyWarning( ...
                @() sem.targeting.buildTargets(seg, calibration, config), ...
                'sem:targeting:buildTargets:cellsOutsideDmd');
        end

        function buildTargets_requires_affine(tc)
            config = mockConfig();
            seg = struct('centroids', [1, 2], 'score', 1);
            tc.verifyError(@() sem.targeting.buildTargets(seg, struct(), config), ...
                'sem:targeting:buildTargets:noAffine');
        end
    end
end

% --- Local helpers ---

function config = mockConfig()
config = struct( ...
    'groundTruth', struct('nCells', 12, 'seed', 42), ...
    'fov', struct('widthUm', 300, 'heightUm', 600, 'umPerDmdPx', 0.6, ...
        'layerBoundariesUm', [0, 120, 300, 420, 600]), ...
    'dmd', struct('nRows', 800, 'nCols', 1280, 'spotRadiusPx', 17));
end
