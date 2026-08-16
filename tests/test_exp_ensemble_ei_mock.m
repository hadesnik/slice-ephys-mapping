classdef test_exp_ensemble_ei_mock < matlab.unittest.TestCase
    %test_exp_ensemble_ei_mock End-to-end mock E/I session: both VC blocks
    %   run, the identical ensemble set is replayed across them, every
    %   stim trial carries complete ephys metadata, and the session dir has
    %   the full on-disk anatomy the Python pipeline consumes (targets,
    %   ensembles, ground truth, per-block trials + session.mat).

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
        function full_session_anatomy(tc)
            config = smallConfig(tc.TmpDir);
            result = sem.experiments.exp_ensemble_ei(config, 'ei_test', ...
                struct('seed', 77));

            tc.verifyEqual(numel(result.blockResults), 2);
            tc.verifyEqual(result.ensembleIdsPerBlock{1}, result.ensembleIdsPerBlock{2});

            sd = result.sessionDir;
            tc.verifyTrue(isfile(fullfile(sd, 'targets.mat')));
            tc.verifyTrue(isfile(fullfile(sd, 'ensembles.mat')));
            tc.verifyTrue(isfile(fullfile(sd, 'ground_truth.mat')));
            tc.verifyTrue(isfile(fullfile(sd, 'config_snapshot.mat')));
            tc.verifyTrue(isfile(fullfile(sd, 'log.txt')));

            for b = 1:2
                br = result.blockResults{b};
                tc.verifyTrue(isfile(br.sessionMatPath));
                metaFiles = dir(fullfile(br.blockDir, 'trials', '*_meta.mat'));
                tc.verifyEqual(numel(metaFiles), numel(br.trials));
            end
        end

        function metadata_complete_and_holdings_differ(tc)
            config = smallConfig(tc.TmpDir);
            result = sem.experiments.exp_ensemble_ei(config, 'ei_meta', ...
                struct('seed', 78));

            holdings = zeros(1, 2);
            for b = 1:2
                br = result.blockResults{b};
                stimSeen = false;
                for i = 1:numel(br.trials)
                    tr = br.trials{i};
                    e = tr.metadata.ephys;
                    tc.verifyEqual(e.schemaVersion, 1);
                    tc.verifyTrue(ismember(e.clampMode, {'VC', 'IC'}));
                    tc.verifyTrue(all(isfield(e.gains, {'commandVcMvPerV', ...
                        'commandIcPaPerV', 'scaledVcPaPerV', 'scaledIcMvPerMv'})));
                    tc.verifyTrue(ischar(e.kind));
                    if strcmp(e.kind, 'ensemble')
                        stimSeen = true;
                        tc.verifyFalse(isnan(e.ensembleId));
                        tc.verifyFalse(isnan(e.stimOnsetSampleInSnippet));
                    end
                    holdings(b) = e.holdingMv;
                end
                tc.verifyTrue(stimSeen);
            end
            tc.verifyEqual(sort(holdings), [-70, 10]);
        end

        function e_and_i_have_opposite_sign(tc)
            % The scientific core in miniature: the same ensembles evoke
            % net-inward charge at -70 and net-outward charge at +10.
            config = smallConfig(tc.TmpDir);
            config.groundTruth.noiseRmsPa = 1;
            result = sem.experiments.exp_ensemble_ei(config, 'ei_sign', ...
                struct('seed', 79));
            gain = sem.util.Units.gainFromConfig(config.ephys);
            meanCharge = zeros(1, 2);
            holdings = zeros(1, 2);
            for b = 1:2
                br = result.blockResults{b};
                charges = [];
                for i = 1:numel(br.trials)
                    tr = br.trials{i};
                    e = tr.metadata.ephys;
                    if ~strcmp(e.kind, 'ensemble') || ~strcmp(tr.status, 'complete')
                        continue
                    end
                    ai = sem.util.Units.scaledDaqVoltsToCell( ...
                        tr.data.aiData(:, e.aiChannelMap.scaledOutput), 'VC', gain);
                    o = round(e.stimOnsetSampleInSnippet);
                    fs = tr.daq_master_sample_rate_hz;
                    base = mean(ai(1:max(1, o - 1)));
                    win = ai(o + round(0.002 * fs) : min(end, o + round(0.06 * fs)));
                    charges(end+1) = sum(win - base) / fs; %#ok<AGROW>
                    holdings(b) = e.holdingMv;
                end
                meanCharge(b) = mean(charges);
            end
            eIdx = holdings == -70;
            tc.verifyLessThan(meanCharge(eIdx), 0);      % net inward at -70
            tc.verifyGreaterThan(meanCharge(~eIdx), 0);  % net outward at +10
        end
    end
end

% --- Local helpers ---

function config = smallConfig(tmpDir)
thisDir = fileparts(mfilename('fullpath'));
config = tfp.io.loadConfig(fullfile(thisDir, '..', 'configs', 'mock.yaml'));
config.paths.dataDir = tmpDir;
config.groundTruth.nCells = 10;
config.groundTruth.opsinNegFraction = 0;
config.groundTruth.connectedFraction = 0.6;
config.ensemble.nEnsembles = 8;
config.ensemble.nBlank = 1;
config.ensemble.sizeMin = 3;
config.ensemble.sizeMax = 6;
config.ensemble.blocks = {'VC-70', 'VC+10'};
config.ephys.sealTest_everyNTrials = 50;
config.timing.itiMeanS = 0.01;
config.timing.itiJitterS = 0.005;
config.dmd.chunkSize = 10;
config.ui.liveFigure = false;
end
