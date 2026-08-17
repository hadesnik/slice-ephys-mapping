classdef test_slice_ephys_app < matlab.unittest.TestCase
    %test_slice_ephys_app The merged app: one window, patch mode and experiment
    %   mode over one rig.
    %
    %   Headless-safe: the app is built with Visible='off'. uifigure and its
    %   widgets construct fine under `matlab -nodisplay` on this platform, so
    %   these run in the normal suite alongside everything else.
    %
    %   What is pinned here is the wiring, not the pixels: both tabs exist and
    %   own their panels, patch mode actually acquires through the rig adapter
    %   and updates the trends, a mapping block runs to completion from the
    %   Experiment tab, Abort leaves a saved partial block, and shutdown is
    %   idempotent.

    properties
        TmpDir
        App
    end

    methods (TestMethodSetup)
        function makeTmp(tc)
            tc.TmpDir = tempname();
            mkdir(tc.TmpDir);
        end
    end

    methods (TestMethodTeardown)
        function cleanUp(tc)
            if ~isempty(tc.App) && isvalid(tc.App)
                tc.App.shutdown();
            end
            tc.App = [];
            if isfolder(tc.TmpDir)
                rmdir(tc.TmpDir, 's');
            end
        end
    end

    methods (Test)

        function app_builds_both_modes_over_one_rig(tc)
            tc.App = tc.buildApp(4);

            tc.verifyClass(tc.App.Figure, 'matlab.ui.Figure');
            tc.verifyNotEmpty(tc.App.PatchWindow);
            tc.verifyNotEmpty(tc.App.ExperimentPanel);

            % Patch mode drives the rig through the adapter, not a fake backend.
            tc.verifyClass(tc.App.PatchWindow.Daq, 'sem.hardware.PatchDaqAdapter');
            tc.verifyClass(tc.App.Telegraph, 'sem.hardware.ConfigTelegraph');
            % Both modes share one DAQ object.
            tc.verifySameHandle(tc.App.PatchWindow.Daq.daq, tc.App.Daq);
            tc.verifySameHandle(tc.App.BlockRunner.daq, tc.App.Daq);

            % Two tabs in one window.
            tabs = findall(tc.App.Figure, 'Type', 'uitab');
            tc.verifyNumElements(tabs, 2);
            tc.verifyTrue(all(ismember({'Patch', 'Experiment'}, {tabs.Title})));

            % The embedded panel set did not open a second window.
            tc.verifySameHandle(tc.App.PatchWindow.Figure, tc.App.Figure);
        end

        function gui_defaults_come_from_the_rig_config(tc)
            tc.App = tc.buildApp(4);
            cfg = tc.App.PatchWindow.Config;
            semCfg = tc.App.Config;

            tc.verifyEqual(cfg.sampleRateHz, semCfg.daq.sampleRate);
            tc.verifyEqual(cfg.sealTest.preMs, semCfg.ephys.sealTest_preMs);
            tc.verifyEqual(cfg.sealTest.stepMs, semCfg.ephys.sealTest_stepMs);
            tc.verifyEqual(cfg.sealTest.amplitudeVcMv, semCfg.ephys.sealTest_amplitudeVcMv);
        end

        function patch_mode_acquires_and_updates_trends(tc)
            tc.App = tc.buildApp(4);
            runner = tc.App.PatchWindow.Runner;

            % One deterministic sweep: start() runs trial 1 on this stack.
            runner.start();
            runner.stop();

            res = runner.lastTrialResult;
            tc.assertNotEmpty(res, 'patch mode produced no sweep');
            tc.verifyFalse(isempty(res.aiCellUnits));
            % Rs/Ri recovered from the mock cell through the rig adapter.
            tc.verifyTrue(isfinite(res.rsMohm) && res.rsMohm > 0);
            tc.verifyTrue(isfinite(res.riMohm) && res.riMohm > 0);

            % The trend panel drew the point.
            trendLines = findall(tc.App.PatchWindow.TrendPlotsPanel.Panel, 'Type', 'line');
            tc.verifyNotEmpty(trendLines);
        end

        function experiment_tab_runs_a_block_to_completion(tc)
            tc.App = tc.buildApp(4);
            runner = tc.App.BlockRunner;

            result = runner.runBlock(tc.App.ExperimentPanel.BlockPlans{1});

            tc.verifyFalse(result.aborted);
            tc.verifyEqual(runner.state, 'Idle');
            tc.verifyTrue(isfile(result.sessionMatPath));
            tc.verifyEqual(runner.trialIndex, 4);
        end

        function abort_from_the_gui_leaves_a_saved_partial_block(tc)
            tc.App = tc.buildApp(10);
            runner = tc.App.BlockRunner;

            % Stand in for the Abort button: fire it from a trial event, which
            % is exactly the path a button callback takes during pause().
            lh = event.listener(runner, 'TrialFinished', ...
                @(s, ~) tc.abortAfter(s, 2)); %#ok<NASGU>

            result = runner.runBlock(tc.App.ExperimentPanel.BlockPlans{1});

            tc.verifyTrue(result.aborted);
            tc.verifyEqual(runner.trialIndex, 2);
            tc.verifyTrue(isfile(result.sessionMatPath), ...
                'an aborted block must still be saved');
        end

        function shutdown_is_idempotent(tc)
            tc.App = tc.buildApp(4);
            fig = tc.App.Figure;

            tc.App.shutdown();
            tc.App.shutdown();   % must not error

            tc.verifyFalse(isvalid(fig));
        end
    end

    methods (Access = private)

        function app = buildApp(tc, nEnsembles)
            config = smallConfig(tc.TmpDir);
            config.ensemble.nEnsembles = nEnsembles;

            targets = sem.targeting.mockTargets(config);
            targets.patchedCellId = 1;
            model = sem.sim.makeGroundTruthNetwork(config, targets);

            [dmd, daq] = sem.hardware.makeRig(config);
            daq.attachNetworkModel(model);

            ens = sem.protocol.generateEnsembles(targets, config, 55);
            config.ensemble.blocks = {'VC-70'};
            plans = sem.protocol.planBlocks(ens, targets, config);

            app = sem.gui.SliceEphysApp(config, ...
                'SessionDir', fullfile(tc.TmpDir, 'session'), ...
                'BlockPlans', {plans(1)}, ...
                'Visible', "off", ...
                'Rig', {dmd, daq});
        end

        function abortAfter(~, runner, n)
            if runner.trialIndex >= n
                runner.abort();
            end
        end
    end
end

% --- local helpers ---------------------------------------------------------

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
