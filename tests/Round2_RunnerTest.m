classdef Round2_RunnerTest < matlab.unittest.TestCase
    % Round2_RunnerTest  Tests for patchclamp.acquisition.ExperimentRunner.
    %
    % These tests run on macOS via FakeBackend + FakeTelegraph. The runner
    % uses a one-shot `timer` for the inter-trial interval, so each test
    % yields the main thread with `pause` so the timer callback can fire.

    properties
        TempFiles string = string.empty(1,0)
    end

    methods (TestMethodTeardown)
        function deleteTempFiles(testCase)
            for k = 1:numel(testCase.TempFiles)
                p = testCase.TempFiles(k);
                if exist(p, "file") == 2
                    delete(p);
                end
            end
            testCase.TempFiles = string.empty(1,0);

            % Sweep any stray runner timers (a leak would itself be a bug,
            % but a leak in one test shouldn't pollute the next).
            ts = timerfindall('Tag', 'patchclamp.runner.iti');
            for k = 1:numel(ts)
                try
                    stop(ts(k));
                catch
                end
                try
                    delete(ts(k));
                catch
                end
            end
        end
    end

    methods (Test)

        function testInitialStateIsIdle(testCase)
            [runner, ~, ~] = testCase.makeRunner();
            testCase.verifyEqual(runner.state, "Idle");
            testCase.verifyEqual(runner.trialCount, uint32(0));
        end

        function testStartTransitionsToRunningAndFiresStateChanged(testCase)
            [runner, ~, ~] = testCase.makeRunner();

            seen = strings(1,0);
            lh = addlistener(runner, 'StateChanged', @(src,~) onState(src));
            cleanup = onCleanup(@() delete(lh)); %#ok<NASGU>

            function onState(src)
                seen(end+1) = src.state; %#ok<AGROW>
            end

            runner.start();
            % After start() returns, at least the Running transition must
            % have been observed. The runner may have additionally
            % synchronously completed the first trial and armed the ITI
            % timer, but it must not yet be back at Idle.
            testCase.verifyTrue(any(seen == "Running"), "Expected a StateChanged to Running.");
            testCase.verifyEqual(runner.state, "Running");

            runner.stop();
            testCase.verifyEqual(runner.state, "Idle");
        end

        function testRunsFirstTrialAndFiresTrialFinished(testCase)
            % Use a short trial that still satisfies Trial.compose's fixed
            % 300 ms preamble (the preamble is structural, not configurable).
            [runner, ~, ~] = testCase.makeRunner( ...
                'trialLengthSec', 0.35, ...
                'sampleRateHz',   20000, ...
                'itiSec',         0.05, ...
                'sealTest', struct('amplitudeVcMv', -5, 'amplitudeIcPa', -100, ...
                                   'preMs', 10, 'stepMs', 20, 'postMs', 10));

            finished = false;
            lh = addlistener(runner, 'TrialFinished', @(~,~) onFinished());
            cleanup = onCleanup(@() delete(lh)); %#ok<NASGU>
            function onFinished()
                finished = true;
            end

            runner.start();

            testCase.waitFor(@() finished, 5.0);
            testCase.verifyTrue(finished, "TrialFinished did not fire within 5 s.");

            tr = runner.lastTrialResult;
            testCase.verifyTrue(isstruct(tr));
            requiredFields = ["aiCellUnits","aoCommandCellUnits","aoLedVolts", ...
                              "rsMohm","riMohm","holding","holdingUnit","mode", ...
                              "sampleRateHz","timestamp","gainSnapshot","trialIndex"];
            for f = requiredFields
                testCase.verifyTrue(isfield(tr, f), sprintf("lastTrialResult missing %s", f));
            end
            testCase.verifyEqual(tr.trialIndex, uint32(0));
            testCase.verifyEqual(tr.mode, "VC");
            testCase.verifyEqual(numel(tr.aiCellUnits), 20000 * 0.35);

            runner.stop();
            testCase.verifyEqual(runner.state, "Idle");
        end

        function testRunsMultipleTrialsAtItiPace(testCase)
            [runner, ~, ~] = testCase.makeRunner( ...
                'trialLengthSec', 0.35, ...
                'itiSec',         0.05, ...
                'sealTest', struct('amplitudeVcMv', -5, 'amplitudeIcPa', -100, ...
                                   'preMs', 10, 'stepMs', 20, 'postMs', 10));

            runner.start();

            % Real wall-clock here is dominated by ITI gaps -- FakeBackend.run()
            % synthesises the trace immediately, it doesn't actually wait. So
            % each trial cycle is ~itiSec wall-clock. Wait long enough for ~3
            % cycles plus a margin.
            testCase.pauseFor(0.3);

            runner.stop();
            testCase.verifyGreaterThan(runner.trialCount, uint32(2), ...
                "Expected more than 2 trials in ~0.3 s with itiSec=0.05.");
            testCase.verifyEqual(runner.state, "Idle");
        end

        function testStopAllowsCurrentTrialToFinishThenIdles(testCase)
            [runner, ~, ~] = testCase.makeRunner( ...
                'trialLengthSec', 0.35, ...
                'itiSec',         0.1, ...
                'sealTest', struct('amplitudeVcMv', -5, 'amplitudeIcPa', -100, ...
                                   'preMs', 10, 'stepMs', 20, 'postMs', 10));

            runner.start();

            % Wait for at least one trial to have completed.
            testCase.waitFor(@() runner.trialCount >= uint32(1), 5.0);

            beforeStop = runner.trialCount;
            runner.stop();

            testCase.verifyEqual(runner.state, "Idle");
            testCase.verifyGreaterThanOrEqual(runner.trialCount, beforeStop, ...
                "trialCount must not regress on stop.");

            % No ITI timers left armed.
            ts = timerfindall('Tag', 'patchclamp.runner.iti');
            testCase.verifyEmpty(ts, "No runner ITI timers should remain after stop().");
        end

        function testHdf5WriterReceivesEveryTrial(testCase)
            filePath = string([tempname '.h5']);
            testCase.TempFiles(end+1) = filePath;

            [runner, ~, ~] = testCase.makeRunner( ...
                'trialLengthSec', 0.35, ...
                'itiSec',         0.05, ...
                'sealTest', struct('amplitudeVcMv', -5, 'amplitudeIcPa', -100, ...
                                   'preMs', 10, 'stepMs', 20, 'postMs', 10), ...
                'withWriter',     filePath);

            runner.start();
            testCase.waitFor(@() runner.trialCount >= uint32(2), 5.0);
            runner.stop();

            % Reach into the runner's writer via the same path the caller has:
            % we constructed it, so we have a reference -- but our helper hands
            % ownership to the runner. Re-open by peeking the file directly.
            count = patchclamp.storage.Hdf5Writer.peekTrialCount(filePath);
            testCase.verifyEqual(count, runner.trialCount, ...
                "Writer must receive every trial the runner completes.");
        end

        function testModeChangeBetweenTrialsIsPickedUpOnNext(testCase)
            [runner, telegraph, ~] = testCase.makeRunner( ...
                'trialLengthSec', 0.35, ...
                'itiSec',         0.05, ...
                'sealTest', struct('amplitudeVcMv', -5, 'amplitudeIcPa', -100, ...
                                   'preMs', 10, 'stepMs', 20, 'postMs', 10));

            runner.start();
            testCase.waitFor(@() runner.trialCount >= uint32(1), 5.0);
            testCase.verifyEqual(runner.lastTrialResult.mode, "VC");

            % Flip the telegraph; the next trial should pick it up.
            firstCount = runner.trialCount;
            telegraph.setMode("IC");

            testCase.waitFor(@() runner.trialCount > firstCount, 5.0);
            testCase.verifyEqual(runner.lastTrialResult.mode, "IC", ...
                "Mode must be re-latched at each trial start.");

            runner.stop();
        end

        function testErrorInPipelineTransitionsToIdleAndFiresAcquisitionError(testCase)
            % Contract: a trial that throws must drive the runner back to Idle
            % and fire AcquisitionError; lastError must be set.
            %
            % Triggering mechanism: pass the runner a Hdf5Writer that was
            % closed before start(). On the first trial, writer.appendTrial
            % raises "NotOpen", which the runner must intercept. MATLAB does
            % not allow auxiliary classdefs (e.g. a BrokenBackend stub) in a
            % test file, so we trigger the error path through an existing
            % component whose contract documents a throwing condition.
            filePath = string([tempname '.h5']);
            testCase.TempFiles(end+1) = filePath;

            telegraph = patchclamp.hardware.FakeTelegraph();
            backend   = patchclamp.hardware.FakeBackend(telegraph);
            backend.rngSeed = 1;

            cfg = patchclamp.config.TrialConfig.defaultConfig();
            cfg.trialLengthSec = 0.35;
            cfg.itiSec         = 0.05;
            cfg.sealTest.preMs  = 10;
            cfg.sealTest.stepMs = 20;
            cfg.sealTest.postMs = 10;

            sessionMeta = struct('cellId', "broken-cell", 'config', cfg);
            writer = patchclamp.storage.Hdf5Writer(filePath, sessionMeta);
            writer.close();   % deliberately closed before the runner uses it

            runner = patchclamp.acquisition.ExperimentRunner(backend, telegraph, writer, cfg);

            sawError = false;
            lh = addlistener(runner, 'AcquisitionError', @(~,~) onErr());
            cleanup = onCleanup(@() delete(lh)); %#ok<NASGU>
            function onErr()
                sawError = true;
            end

            runner.start();
            testCase.waitFor(@() sawError, 5.0);

            testCase.verifyTrue(sawError, "AcquisitionError did not fire.");
            testCase.verifyEqual(runner.state, "Idle");
            testCase.verifyNotEmpty(runner.lastError, "lastError must be set after a pipeline error.");
            testCase.verifyClass(runner.lastError, ?MException);
        end

        function testNoLeakedTimers(testCase)
            [runner, ~, ~] = testCase.makeRunner( ...
                'trialLengthSec', 0.35, ...
                'itiSec',         0.05, ...
                'sealTest', struct('amplitudeVcMv', -5, 'amplitudeIcPa', -100, ...
                                   'preMs', 10, 'stepMs', 20, 'postMs', 10));

            runner.start();
            testCase.waitFor(@() runner.trialCount >= uint32(1), 5.0);
            runner.stop();

            ts = timerfindall('Tag', 'patchclamp.runner.iti');
            testCase.verifyEmpty(ts, "Runner ITI timers leaked past stop().");
        end

    end

    methods (Access = private)

        function [runner, telegraph, backend] = makeRunner(testCase, varargin)
            % Build a runner with overridable config bits. opts:
            %   'trialLengthSec', 'sampleRateHz', 'itiSec', 'sealTest', 'withWriter'

            p = inputParser();
            p.addParameter('trialLengthSec', 0.35);
            p.addParameter('sampleRateHz',   20000);
            p.addParameter('itiSec',         0.05);
            p.addParameter('sealTest',       []);
            p.addParameter('withWriter',     "");
            p.parse(varargin{:});

            cfg = patchclamp.config.TrialConfig.defaultConfig();
            cfg.trialLengthSec = p.Results.trialLengthSec;
            cfg.sampleRateHz   = p.Results.sampleRateHz;
            cfg.itiSec         = p.Results.itiSec;
            if ~isempty(p.Results.sealTest)
                cfg.sealTest = p.Results.sealTest;
            end

            telegraph = patchclamp.hardware.FakeTelegraph();
            backend   = patchclamp.hardware.FakeBackend(telegraph);
            backend.rngSeed = 1;

            writer = [];
            wp = string(p.Results.withWriter);
            if strlength(wp) > 0
                sessionMeta = struct('cellId', "test-cell", 'config', cfg);
                writer = patchclamp.storage.Hdf5Writer(wp, sessionMeta);
            end

            runner = patchclamp.acquisition.ExperimentRunner(backend, telegraph, writer, cfg);
        end

        function waitFor(~, predicate, timeoutSec)
            % Pump events until predicate() is true or timeout elapses.
            t0 = tic;
            while toc(t0) < timeoutSec
                if predicate()
                    return;
                end
                pause(0.01);
            end
        end

        function pauseFor(~, sec)
            t0 = tic;
            while toc(t0) < sec
                pause(0.01);
            end
        end
    end
end
