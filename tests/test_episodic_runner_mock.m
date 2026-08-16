classdef test_episodic_runner_mock < matlab.unittest.TestCase
    %test_episodic_runner_mock The block engine end-to-end against the mock
    %   rig: onset monotonicity, per-trial slicing windows, seal-test
    %   insertion (start / interleaved / end), continue-on-error policy, the
    %   end-at-holding AO convention, and on-disk saveTrial output.

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
        function block_runs_and_saves(tc)
            [runner, blockPlan, daq] = makeFixture(tc.TmpDir, 8);
            result = runner.runBlock(blockPlan);
            tc.verifyEqual(result.nFailed, 0);

            % 8 stim trials + opening/closing seal + one interleaved (every 5).
            nTrials = numel(result.trials);
            tc.verifyEqual(nTrials, 8 + 3);

            % Onset anchors strictly increase in queue order.
            onsets = cellfun(@(t) double(t.t_onset_daq_samples), result.trials);
            tc.verifyTrue(all(diff(onsets) > 0));

            % Every trial completed with a sliced AI snippet + onset marker.
            for i = 1:numel(result.trials)
                tr = result.trials{i};
                tc.verifyEqual(tr.status, 'complete');
                tc.verifyFalse(isempty(tr.data.aiData));
                tc.verifyFalse(isnan(tr.metadata.ephys.stimOnsetSampleInSnippet));
            end

            % On disk: meta+raw per trial under the block dir.
            metaFiles = dir(fullfile(result.blockDir, 'trials', '*_meta.mat'));
            rawFiles = dir(fullfile(result.blockDir, 'trials', '*_raw.mat'));
            tc.verifyEqual(numel(metaFiles), nTrials);
            tc.verifyEqual(numel(rawFiles), nTrials);
            tc.verifyTrue(isfile(result.sessionMatPath));

            % Seal tests analyzed: opening + interleaved + closing.
            tc.verifyEqual(numel(result.sealTests), 3);
            tc.verifyTrue(all(isfinite([result.sealTests.rsMohm])));
            tc.verifyFalse(daq.isRunning);
        end

        function slicing_window_matches_config(tc)
            [runner, blockPlan, ~, config] = makeFixture(tc.TmpDir, 3);
            result = runner.runBlock(blockPlan);
            fs = config.daq.sampleRate;
            for i = 1:numel(result.trials)
                tr = result.trials{i};
                if ~strcmp(tr.metadata.ephys.kind, 'sealTest')
                    expected = round(config.timing.preS * fs) ...
                        + round(tr.duration_s * fs) + round(config.timing.postS * fs);
                    tc.verifyEqual(size(tr.data.aiData, 1), expected, 'AbsTol', 3);
                    tc.verifyEqual(tr.metadata.ephys.stimOnsetSampleInSnippet, ...
                        round(config.timing.preS * fs) + 1, 'AbsTol', 2);
                end
            end
        end

        function cell_command_ends_at_holding(tc)
            % The AO idle convention the mock's command reconstruction (and
            % the real NI behavior) relies on: every queued waveform's cell
            % column must end at the block holding, laser column at 0.
            [runner, blockPlan, daq] = makeFixture(tc.TmpDir, 3);
            runner.runBlock(blockPlan);
            events = daq.getEvents();
            gain = sem.util.Units.gainFromConfig(struct());
            holdVolts = sem.util.Units.commandCellToDaqVolts(-70, 'VC', gain);
            tc.verifyGreaterThan(numel(events), 3);
            for e = 2:numel(events)   % event 1 is the ramp itself
                tc.verifyEqual(events(e).samples(end, 2), holdVolts, 'AbsTol', 1e-9);
                tc.verifyEqual(events(e).samples(end, 1), 0, 'AbsTol', 1e-12);
            end
        end

        function per_trial_failure_continues_block(tc)
            % A failing trial is marked failed and the block CONTINUES: a
            % 1x2 laserVolts makes the waveform concatenation throw a plain
            % MATLAB error (non-hardware family) inside runStimTrial.
            [runner, blockPlan] = makeFixture(tc.TmpDir, 4);
            blockPlan.trials(2).laserVolts = [2, 2];
            result = runner.runBlock(blockPlan);
            tc.verifyEqual(result.nFailed, 1);
            statuses = cellfun(@(t) string(t.status), result.trials);
            tc.verifyEqual(nnz(statuses == "failed"), 1);
            % Failed trials are still written to disk (failed + complete).
            metaFiles = dir(fullfile(result.blockDir, 'trials', '*_meta.mat'));
            tc.verifyEqual(numel(metaFiles), numel(result.trials));
        end

        function chunk_level_pattern_failure_aborts(tc)
            % Pattern-build failures happen at CHUNK level, outside the
            % per-trial catch: they abort the block loudly (nothing valid
            % could be presented from that chunk).
            [runner, blockPlan] = makeFixture(tc.TmpDir, 4);
            blockPlan.trials(2).fillFractions = ...
                NaN(numel(blockPlan.trials(2).fillFractions), 1);
            tc.verifyError(@() runner.runBlock(blockPlan), ...
                'tfp:patterns:fillFactorEnsemble:badFractions');
        end
    end
end

% --- Local helpers ---

function [runner, blockPlan, daq, config] = makeFixture(tmpDir, nEnsembles)
config = smallConfig(tmpDir);
config.ensemble.nEnsembles = nEnsembles;

targets = sem.targeting.mockTargets(config);
targets.patchedCellId = 1;
model = sem.sim.makeGroundTruthNetwork(config, targets);

[dmd, daq] = sem.hardware.makeRig(config);
daq.attachNetworkModel(model);

ens = sem.protocol.generateEnsembles(targets, config, 55);
config.ensemble.blocks = {'VC-70'};
plans = sem.protocol.planBlocks(ens, targets, config);
blockPlan = plans(1);

runner = sem.protocol.EpisodicRunner(dmd, daq, config, ...
    fullfile(tmpDir, 'session'));
end

function config = smallConfig(tmpDir)
thisDir = fileparts(mfilename('fullpath'));
config = tfp.io.loadConfig(fullfile(thisDir, '..', 'configs', 'mock.yaml'));
config.paths.dataDir = tmpDir;
config.groundTruth.nCells = 10;
config.groundTruth.opsinNegFraction = 0;
config.ensemble.sizeMin = 2;
config.ensemble.sizeMax = 4;
config.ensemble.nBlank = 0;
config.ephys.sealTest_everyNTrials = 5;
config.timing.itiMeanS = 0.01;
config.timing.itiJitterS = 0.005;
config.dmd.chunkSize = 6;
config.ui.liveFigure = false;
end
