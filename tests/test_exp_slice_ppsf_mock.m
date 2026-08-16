classdef test_exp_slice_ppsf_mock < matlab.unittest.TestCase
    %test_exp_slice_ppsf_mock Mock PPSF factorial: runs end-to-end in CC,
    %   produces a per-trial quick-look table, and the on-soma /
    %   high-power conditions depolarize more than the far-offset ones —
    %   i.e. the factorial actually samples the ground-truth PPSF.

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
        function runs_and_summarizes(tc)
            config = smallConfig(tc.TmpDir);
            result = sem.experiments.exp_slice_ppsf(config, 'ppsf_test', ...
                struct('seed', 5));
            nCond = numel(result.conditions);
            tc.verifyEqual(nCond, ...
                config.ppsf.nReps * numel(config.ppsf.laserVoltsLevels) ...
                * numel(config.ppsf.fillFactors) ...
                * (2 * config.ppsf.nPointsPerHalfAxis + 1)^2);  % gaussianGrid2D size
            tc.verifyEqual(numel(result.trialTable), nCond);
            tc.verifyEqual(result.blockResult.nFailed, 0);
            % CC block: spike counts populated (possibly zero), units mV.
            tc.verifyTrue(all(~isnan([result.trialTable.nSpikes])));
        end

        function response_falls_off_with_distance(tc)
            config = smallConfig(tc.TmpDir);
            result = sem.experiments.exp_slice_ppsf(config, 'ppsf_falloff', ...
                struct('seed', 6));
            t = result.trialTable;
            maxPower = max([t.laserVolts]);
            maxFill = max([t.fillFactor]);
            sel = [t.laserVolts] == maxPower & [t.fillFactor] == maxFill;
            d = [t(sel).distanceUm];
            r = [t(sel).peakDepolMv];
            nearResp = mean(r(d <= 10));
            farResp = mean(r(d >= 40));
            tc.verifyGreaterThan(nearResp, 5);          % strong on-soma depol (mV)
            tc.verifyLessThan(farResp, nearResp / 3);   % clear lateral falloff
        end
    end
end

% --- Local helpers ---

function config = smallConfig(tmpDir)
thisDir = fileparts(mfilename('fullpath'));
config = tfp.io.loadConfig(fullfile(thisDir, '..', 'configs', 'mock.yaml'));
config.paths.dataDir = tmpDir;
config.groundTruth.nCells = 6;
config.groundTruth.opsinNegFraction = 0;
config.groundTruth.noiseRmsMv = 0.1;
config.ppsf.laserVoltsLevels = [1.0, 3.0];
config.ppsf.fillFactors = [0.5, 1.0];
config.ppsf.nPointsPerHalfAxis = 2;
config.ppsf.offsetsMaxUm = 50;
config.ppsf.nReps = 1;
config.ephys.sealTest_everyNTrials = 100;
config.timing.itiMeanS = 0.01;
config.timing.itiJitterS = 0.002;
config.dmd.chunkSize = 12;
config.ui.liveFigure = false;
end
