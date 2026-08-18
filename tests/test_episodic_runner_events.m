classdef test_episodic_runner_events < matlab.unittest.TestCase
    %test_episodic_runner_events The GUI-facing surface of the block engine:
    %   events, mid-block abort, and the injectable operator prompt / seal-rule
    %   hooks. These are what let a GUI drive runBlock without restructuring the
    %   loop, so each is pinned here.
    %
    %   The abort test is the load-bearing one: it asserts that a listener
    %   calling abort() during the block actually stops it early AND that the
    %   partial block is still stopped, sliced, saved and analyzed — a partial
    %   block must remain a valid block, not a corrupt one.

    properties
        TmpDir
        Events = {}
    end

    methods (TestMethodSetup)
        function makeTmp(tc)
            tc.TmpDir = tempname();
            mkdir(tc.TmpDir);
            tc.Events = {};
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

        function fires_progress_and_state_events(tc)
            [runner, blockPlan] = makeFixture(tc.TmpDir, 6);
            lh1 = event.listener(runner, 'TrialFinished', ...
                @(s, ~) tc.record('TrialFinished', s.trialIndex)); %#ok<NASGU>
            lh2 = event.listener(runner, 'StateChanged', ...
                @(s, ~) tc.record('StateChanged', s.state)); %#ok<NASGU>

            tc.verifyEqual(runner.state, 'Idle');
            result = runner.runBlock(blockPlan);

            % One TrialFinished per stim trial, counting up.
            idx = tc.valuesFor('TrialFinished');
            tc.verifyEqual(numel(idx), 6);
            tc.verifyEqual([idx{:}], 1:6);

            % Running on entry, Idle again on exit.
            states = tc.valuesFor('StateChanged');
            tc.verifyEqual(states{1}, 'Running');
            tc.verifyEqual(states{end}, 'Idle');
            tc.verifyEqual(runner.state, 'Idle');
            tc.verifyFalse(result.aborted);
            tc.verifyEqual(runner.nTrials, 6);
        end

        function abort_midblock_saves_a_valid_partial_block(tc)
            [runner, blockPlan] = makeFixture(tc.TmpDir, 12);
            % Stop after the 3rd stim trial, the way a Stop button would.
            lh = event.listener(runner, 'TrialFinished', ...
                @(s, ~) tc.abortAfter(s, 3)); %#ok<NASGU>

            result = runner.runBlock(blockPlan);

            tc.verifyTrue(result.aborted);
            tc.verifyEqual(runner.trialIndex, 3, ...
                'the block must stop at the next trial boundary after abort()');
            tc.verifyEqual(runner.state, 'Idle');

            % The partial block is still a real block: session stopped, trials
            % sliced and completed, seal tests analyzed, files on disk.
            tc.verifyTrue(isfile(result.sessionMatPath));
            tc.verifyNotEmpty(result.trials);
            tc.verifyTrue(numel(result.trials) < 12);
            for i = 1:numel(result.trials)
                tr = result.trials{i};
                if strcmp(tr.status, 'complete')
                    tc.verifyFalse(isempty(tr.data.aiData));
                end
            end
            tc.verifyNotEmpty(result.sealTests, ...
                'the opening seal test must still be analyzed after an abort');
            tc.verifyTrue(isfolder(fullfile(result.blockDir, 'trials')));

            % The abort is on the record.
            logTxt = fileread(fullfile(fileparts(result.blockDir), 'log.txt'));
            tc.verifyTrue(contains(logTxt, 'block-aborted'));
        end

        function live_trial_snippet_is_available_during_the_block(tc)
            % The GUI plots each trial as it happens rather than waiting for
            % block end. This needs the DAQ's peekContinuousAi; the mock has it.
            [runner, blockPlan] = makeFixture(tc.TmpDir, 5);
            lh = event.listener(runner, 'TrialFinished', ...
                @(s, ~) tc.record('snippet', s.lastTrialSnippet)); %#ok<NASGU>

            runner.runBlock(blockPlan);

            snips = tc.valuesFor('snippet');
            tc.verifyNumElements(snips, 5);
            nonEmpty = cellfun(@(x) ~isempty(x), snips);
            tc.verifyTrue(any(nonEmpty), ...
                'no live snippet reached the listener during the block');
            % In cell units (pA in VC), so a real response, not raw volts.
            first = snips{find(nonEmpty, 1)};
            tc.verifySize(first, [numel(first), 1]);
            tc.verifyTrue(all(isfinite(first)));
            tc.verifyGreaterThan(max(abs(first)), 1, ...
                'a pA-scale trace should not look like raw volts');
        end

        function abort_when_idle_is_a_noop(tc)
            [runner, ~] = makeFixture(tc.TmpDir, 4);
            runner.abort();
            tc.verifyEqual(runner.state, 'Idle');
        end

        function prompt_is_injectable(tc)
            [runner, blockPlan] = makeFixture(tc.TmpDir, 4);
            % A GUI supplies its own prompt; the default would block on stdin.
            runner.promptFcn = @(msg) tc.record('prompt', msg);

            runner.runBlock(blockPlan, struct('interactive', true));

            msgs = tc.valuesFor('prompt');
            tc.verifyNumElements(msgs, 1);
            tc.verifySubstring(msgs{1}, 'MultiClamp Commander');
        end

        function seal_rule_hook_receives_violations(tc)
            % Force the Rs rule to trip by setting an impossible limit.
            [runner, blockPlan] = makeFixture(tc.TmpDir, 4, ...
                struct('rsAbortMohm', 0.001));
            runner.sealRuleFcn = @(info) tc.recordRule(info);

            runner.runBlock(blockPlan);

            rules = tc.valuesFor('sealRule');
            tc.verifyNotEmpty(rules, 'the Rs limit rule must reach the hook');
            tc.verifyEqual(rules{1}.rule, 'rsAboveLimit');
            tc.verifyGreaterThan(rules{1}.value, rules{1}.limit);
        end

        function default_seal_rule_still_warns_and_continues(tc)
            % Scripted sessions must behave exactly as before the hook existed.
            [runner, blockPlan] = makeFixture(tc.TmpDir, 4, ...
                struct('rsAbortMohm', 0.001));

            tc.verifyWarning(@() runner.runBlock(blockPlan), ...
                'sem:protocol:EpisodicRunner:rsAboveLimit');
        end
    end

    methods (Access = private)
        function record(tc, kind, value)
            tc.Events{end+1} = struct('kind', kind, 'value', value);
        end

        function recordRule(tc, info)
            tc.Events{end+1} = struct('kind', 'sealRule', 'value', info);
        end

        function vals = valuesFor(tc, kind)
            vals = {};
            for i = 1:numel(tc.Events)
                if strcmp(tc.Events{i}.kind, kind)
                    vals{end+1} = tc.Events{i}.value; %#ok<AGROW>
                end
            end
        end

        function abortAfter(~, runner, n)
            if runner.trialIndex >= n
                runner.abort();
            end
        end
    end
end

% --- local helpers ---------------------------------------------------------

function [runner, blockPlan, daq, config] = makeFixture(tmpDir, nEnsembles, ephysOverrides)
config = smallConfig(tmpDir);
config.ensemble.nEnsembles = nEnsembles;
if nargin >= 3 && ~isempty(ephysOverrides)
    names = fieldnames(ephysOverrides);
    for k = 1:numel(names)
        config.ephys.(names{k}) = ephysOverrides.(names{k});
    end
end

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
