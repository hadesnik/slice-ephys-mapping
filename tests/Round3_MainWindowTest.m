classdef Round3_MainWindowTest < matlab.unittest.TestCase
    % Round3_MainWindowTest  R3b assembly + wiring tests.
    %
    % Drives MainWindow with FakeTelegraph + FakeBackend in an invisible
    % uifigure. No writer (Writer=[]) so the test never touches disk. Each
    % test gets a fresh window via TestMethodSetup/Teardown so timer state
    % cannot leak between tests.

    properties
        Window
    end

    methods (TestMethodTeardown)
        function tearDownWindow(testCase)
            try
                if ~isempty(testCase.Window) && isvalid(testCase.Window)
                    testCase.Window.shutdown();
                end
            catch
            end
            testCase.Window = [];

            % Sweep any stray runner timers; a leak would itself be a bug
            % but a leak in one test must not pollute the next.
            ts = timerfindall('Tag', 'patchclamp.runner.iti');
            for k = 1:numel(ts)
                try, stop(ts(k)); catch, end
                try, delete(ts(k)); catch, end
            end
        end
    end

    methods (Test)

        function testConstructionWiresAllPanels(testCase)
            w = testCase.makeWindow();
            testCase.verifyClass(w.Figure, "matlab.ui.Figure");
            testCase.verifyNotEmpty(w.ControlsPanel);
            testCase.verifyNotEmpty(w.TrialPlotPanel);
            testCase.verifyNotEmpty(w.TrendPlotsPanel);
            testCase.verifyNotEmpty(w.OptoEditorPanel);
            testCase.verifyNotEmpty(w.CommandEditorPanel);

            testCase.verifyClass(w.ControlsPanel,      "patchclamp.gui.ControlsPanel");
            testCase.verifyClass(w.TrialPlotPanel,     "patchclamp.gui.TrialPlotPanel");
            testCase.verifyClass(w.TrendPlotsPanel,    "patchclamp.gui.TrendPlotsPanel");
            testCase.verifyClass(w.OptoEditorPanel,    "patchclamp.gui.OptoEditorPanel");
            testCase.verifyClass(w.CommandEditorPanel, "patchclamp.gui.CommandEditorPanel");

            testCase.verifyTrue(isvalid(w.ControlsPanel.Panel));
            testCase.verifyTrue(isvalid(w.TrialPlotPanel.Panel));
            testCase.verifyTrue(isvalid(w.TrendPlotsPanel.Panel));
            testCase.verifyTrue(isvalid(w.OptoEditorPanel.Panel));
            testCase.verifyTrue(isvalid(w.CommandEditorPanel.Panel));
        end

        function testInitialModeMirrored(testCase)
            telegraph = patchclamp.hardware.FakeTelegraph(mode = "IC");
            backend   = patchclamp.hardware.FakeBackend(telegraph);
            w = patchclamp.gui.MainWindow( ...
                Daq=backend, Telegraph=telegraph, Writer=[], ...
                Visible="off");
            testCase.Window = w;

            testCase.verifyEqual(string(w.ControlsPanel.ModeLabel.Text), "IC");
            testCase.verifyEqual(string(w.CommandEditorPanel.Mode), "IC");
            ampLabel = findall(w.CommandEditorPanel.Panel, ...
                'Type', 'uilabel', 'Tag', 'amplitudeLabel');
            testCase.verifyNotEmpty(ampLabel);
            testCase.verifySubstring(string(ampLabel(1).Text), "pA");
        end

        function testStartButtonStartsRunner(testCase)
            w = testCase.makeShortTrialWindow();
            w.ControlsPanel.StartButton.ButtonPushedFcn( ...
                w.ControlsPanel.StartButton, struct());

            % start() runs the first trial synchronously, then arms the ITI
            % timer (or stays Idle on error). Accept Running OR a positive
            % trial count.
            testCase.waitFor(@() w.Runner.state == "Running" || ...
                                 w.Runner.trialCount > uint32(0), 5.0);
            testCase.verifyTrue(w.Runner.state == "Running" || ...
                                w.Runner.trialCount > uint32(0));

            w.ControlsPanel.StopButton.ButtonPushedFcn( ...
                w.ControlsPanel.StopButton, struct());
        end

        function testTrialFinishedFlowsToPlots(testCase)
            w = testCase.makeShortTrialWindow();

            w.ControlsPanel.StartButton.ButtonPushedFcn( ...
                w.ControlsPanel.StartButton, struct());

            testCase.waitFor(@() w.Runner.trialCount >= uint32(1), 5.0);

            % Trial plot has at least one Line drawn.
            kids = findall(w.TrialPlotPanel.Panel, 'Type', 'Line');
            testCase.verifyGreaterThanOrEqual(numel(kids), 1, ...
                "TrialPlotPanel should hold at least one line after a trial.");

            % Trend panel has at least one Line child somewhere (the panel
            % uses plot(...) markers which create Line objects).
            trendLines = findall(w.TrendPlotsPanel.Panel, 'Type', 'Line');
            testCase.verifyGreaterThanOrEqual(numel(trendLines), 1, ...
                "TrendPlotsPanel should hold at least one point after a trial.");

            w.ControlsPanel.StopButton.ButtonPushedFcn( ...
                w.ControlsPanel.StopButton, struct());
        end

        function testStopButtonStops(testCase)
            w = testCase.makeShortTrialWindow();

            w.ControlsPanel.StartButton.ButtonPushedFcn( ...
                w.ControlsPanel.StartButton, struct());
            testCase.waitFor(@() w.Runner.trialCount >= uint32(1), 5.0);

            w.ControlsPanel.StopButton.ButtonPushedFcn( ...
                w.ControlsPanel.StopButton, struct());

            testCase.waitFor(@() w.Runner.state == "Idle", 5.0);
            testCase.verifyEqual(w.Runner.state, "Idle");
        end

        function testModeFlipUpdatesUi(testCase)
            w = testCase.makeWindow();
            w.Telegraph.setMode("IC");

            testCase.verifyEqual(string(w.ControlsPanel.ModeLabel.Text), "IC");
            testCase.verifyEqual(string(w.CommandEditorPanel.Mode), "IC");

            ampLabel = findall(w.CommandEditorPanel.Panel, ...
                'Type', 'uilabel', 'Tag', 'amplitudeLabel');
            testCase.verifyNotEmpty(ampLabel);
            testCase.verifySubstring(string(ampLabel(1).Text), "pA");
        end

        function testItiEditPropagatesToRunner(testCase)
            w = testCase.makeWindow();

            field = w.ControlsPanel.ItiField;
            prev = field.Value;
            field.Value = 0.25;
            ev = struct("Value", 0.25, "PreviousValue", prev);
            field.ValueChangedFcn(field, ev);

            % Source-of-truth check: MainWindow.Config tracks the value.
            testCase.verifyEqual(w.Config.itiSec, 0.25);
        end

        function testTrialLengthEditTooShortIsRejected(testCase)
            w = testCase.makeWindow();
            initialLen = w.Config.trialLengthSec;

            field = w.ControlsPanel.TrialLengthField;
            prev = field.Value;
            field.Value = 0.2;
            ev = struct("Value", 0.2, "PreviousValue", prev);
            field.ValueChangedFcn(field, ev);

            % Source-of-truth config unchanged.
            testCase.verifyEqual(w.Config.trialLengthSec, initialLen);
            % Status label surfaces the error.
            testCase.verifySubstring(string(w.ControlsPanel.StatusLabel.Text), "Error");
        end

        function testCloseRequestShutdownIsCleanup(testCase)
            w = testCase.makeWindow();
            w.shutdown();

            testCase.verifyEqual(w.Runner.state, "Idle");
            ts = timerfindall('Tag', 'patchclamp.runner.iti');
            testCase.verifyEmpty(ts, "shutdown must leave no runner timers behind.");

            % Idempotent.
            w.shutdown();
        end

    end

    methods (Access = private)
        function w = makeWindow(testCase)
            telegraph = patchclamp.hardware.FakeTelegraph();
            backend   = patchclamp.hardware.FakeBackend(telegraph);
            backend.rngSeed = 1;
            w = patchclamp.gui.MainWindow( ...
                Daq=backend, Telegraph=telegraph, Writer=[], ...
                Visible="off");
            testCase.Window = w;
        end

        function w = makeShortTrialWindow(testCase)
            telegraph = patchclamp.hardware.FakeTelegraph();
            backend   = patchclamp.hardware.FakeBackend(telegraph);
            backend.rngSeed = 1;
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            cfg.trialLengthSec = 0.35;
            cfg.itiSec         = 0.05;
            cfg.sealTest.preMs  = 10;
            cfg.sealTest.stepMs = 20;
            cfg.sealTest.postMs = 10;
            w = patchclamp.gui.MainWindow( ...
                Daq=backend, Telegraph=telegraph, Writer=[], Config=cfg, ...
                Visible="off");
            testCase.Window = w;
        end

        function waitFor(~, predicate, timeoutSec)
            t0 = tic;
            while toc(t0) < timeoutSec
                if predicate()
                    return;
                end
                pause(0.01);
            end
        end
    end
end
