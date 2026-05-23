classdef MainWindow < handle
    % MainWindow  R3b assembly: a single uifigure hosting the five Round 3a
    % panels and wiring them to an ExperimentRunner against the supplied
    % DAQ + telegraph.
    %
    % Layout (programmatic, no .mlapp):
    %   LEFT column  (350 px)   : ControlsPanel / OptoEditorPanel / CommandEditorPanel
    %   RIGHT column (remainder): TrialPlotPanel (top ~280 px) / TrendPlotsPanel (fills)
    %
    % A Debug menu provides the v1 hook for flipping the FakeTelegraph mode and
    % nudging the gain so the wiring can be exercised without front-panel
    % access. In R4 the MccTelegraph will surface these transitions naturally
    % from front-panel changes.
    %
    % Source-of-truth invariants:
    %   - obj.Config is the GUI's authoritative TrialConfig. Whenever the user
    %     changes a field that lives in the config, MainWindow patches the
    %     struct AND forwards the new copy to the runner via updateConfig().
    %     The runner's in-flight trial keeps the previous config; the next
    %     trial picks up the new one.
    %   - The mode is owned by the telegraph; the GUI mirrors it (claude.md
    %     invariant 3). Flipping the mode does NOT call updateConfig because
    %     the runner re-reads telegraph.getMode() at every trial start.

    properties (SetAccess = private, GetAccess = public)
        Figure
        ControlsPanel
        TrialPlotPanel
        TrendPlotsPanel
        OptoEditorPanel
        CommandEditorPanel
        Runner
        Daq
        Telegraph
        Writer
        Config
    end

    properties (Access = private)
        Listeners        = event.listener.empty(1,0)
        IsShutdown (1,1) logical = false
    end

    methods
        function obj = MainWindow(options)
            arguments
                options.Daq       = []
                options.Telegraph = []
                options.Writer    = []
                options.Config    = patchclamp.config.TrialConfig.defaultConfig()
                options.Visible   (1,1) string = "on"
            end

            % Resolve telegraph + daq. If neither is supplied build a paired
            % FakeTelegraph + FakeBackend so the GUI is testable in isolation.
            if isempty(options.Telegraph) && isempty(options.Daq)
                tg  = patchclamp.hardware.FakeTelegraph();
                daq = patchclamp.hardware.FakeBackend(tg);
            elseif isempty(options.Daq)
                tg  = options.Telegraph;
                daq = patchclamp.hardware.FakeBackend(tg);
            elseif isempty(options.Telegraph)
                daq = options.Daq;
                tg  = daq.Telegraph;
            else
                daq = options.Daq;
                tg  = options.Telegraph;
            end

            patchclamp.config.TrialConfig.validate(options.Config);

            obj.Daq       = daq;
            obj.Telegraph = tg;
            obj.Writer    = options.Writer;
            obj.Config    = options.Config;

            obj.buildFigure(options.Visible);
            obj.buildPanels();

            obj.Runner = patchclamp.acquisition.ExperimentRunner( ...
                obj.Daq, obj.Telegraph, obj.Writer, obj.Config);

            obj.wireListeners();

            % Push initial state into the UI before the telegraph fires anything.
            obj.Telegraph.start();
            initialMode = obj.Telegraph.getMode();
            obj.ControlsPanel.setMode(initialMode);
            obj.ControlsPanel.setGainDisplay(obj.Telegraph.getGain());
            obj.ControlsPanel.setRunningState("Idle");
            obj.ControlsPanel.setTrialCount(0);
            obj.CommandEditorPanel.setMode(initialMode);
            obj.TrialPlotPanel.setMode(initialMode);

            % Push the stimulus-window length into the two editor previews so
            % their "does it fit" checks match what the runner will use.
            w = obj.stimulusWindowSec();
            obj.OptoEditorPanel.setStimulusWindowSec(w);
            obj.CommandEditorPanel.setStimulusWindowSec(w);

            obj.Figure.CloseRequestFcn = @(~,~) obj.shutdown();
        end

        function shutdown(obj)
            if obj.IsShutdown
                return;
            end
            obj.IsShutdown = true;

            % Tear down listeners first so transient state events don't
            % bounce back into half-deleted widgets.
            for k = 1:numel(obj.Listeners)
                try
                    delete(obj.Listeners(k));
                catch
                end
            end
            obj.Listeners = event.listener.empty(1,0);

            try
                if ~isempty(obj.Runner) && isvalid(obj.Runner)
                    obj.Runner.stop();
                end
            catch
            end

            try
                if ~isempty(obj.Telegraph) && isvalid(obj.Telegraph)
                    obj.Telegraph.stop();
                end
            catch
            end

            try
                if ~isempty(obj.Daq) && isvalid(obj.Daq)
                    obj.Daq.cleanup();
                end
            catch
            end

            try
                if ~isempty(obj.Writer) && isvalid(obj.Writer)
                    obj.Writer.close();
                end
            catch
            end

            try
                if ~isempty(obj.Figure) && isvalid(obj.Figure)
                    delete(obj.Figure);
                end
            catch
            end
        end

        function delete(obj)
            obj.shutdown();
        end
    end

    methods (Access = private)
        function buildFigure(obj, visible)
            obj.Figure = uifigure( ...
                "Name", "patchclamp acquisition", ...
                "Position", [100 100 1400 900], ...
                "Visible", visible);

            % Debug menu: the v1 affordance for flipping the FakeTelegraph
            % mode + nudging the gain. R4 will get these signals naturally
            % from the front panel.
            dbgMenu = uimenu(obj.Figure, "Text", "Debug");
            uimenu(dbgMenu, "Text", "Toggle telegraph mode (VC/IC)", ...
                "MenuSelectedFcn", @(~,~) obj.onToggleMode());
            uimenu(dbgMenu, "Text", "Inject fake gain change", ...
                "MenuSelectedFcn", @(~,~) obj.onInjectGainChange());
        end

        function buildPanels(obj)
            outer = uigridlayout(obj.Figure, [1 2]);
            outer.ColumnWidth = {350, '1x'};
            outer.RowHeight   = {'1x'};
            outer.Padding     = [6 6 6 6];
            outer.ColumnSpacing = 6;

            leftCol = uigridlayout(outer, [3 1]);
            leftCol.Layout.Row = 1; leftCol.Layout.Column = 1;
            leftCol.RowHeight   = {260, '1x', '1x'};
            leftCol.ColumnWidth = {'1x'};
            leftCol.Padding     = [0 0 0 0];
            leftCol.RowSpacing  = 6;

            rightCol = uigridlayout(outer, [2 1]);
            rightCol.Layout.Row = 1; rightCol.Layout.Column = 2;
            rightCol.RowHeight   = {280, '1x'};
            rightCol.ColumnWidth = {'1x'};
            rightCol.Padding     = [0 0 0 0];
            rightCol.RowSpacing  = 6;

            obj.ControlsPanel       = patchclamp.gui.ControlsPanel(leftCol, obj.Config);
            obj.OptoEditorPanel     = patchclamp.gui.OptoEditorPanel(leftCol);
            obj.CommandEditorPanel  = patchclamp.gui.CommandEditorPanel(leftCol);
            obj.TrialPlotPanel      = patchclamp.gui.TrialPlotPanel(rightCol);
            obj.TrendPlotsPanel     = patchclamp.gui.TrendPlotsPanel(rightCol);
        end

        function wireListeners(obj)
            L = event.listener.empty(1,0);

            % ControlsPanel signals.
            L(end+1) = addlistener(obj.ControlsPanel, "StartRequested", ...
                @(~,~) obj.onStartRequested());
            L(end+1) = addlistener(obj.ControlsPanel, "StopRequested", ...
                @(~,~) obj.onStopRequested());
            L(end+1) = addlistener(obj.ControlsPanel, "ItiChanged", ...
                @(~,~) obj.onItiChanged());
            L(end+1) = addlistener(obj.ControlsPanel, "TrialLengthChanged", ...
                @(~,~) obj.onTrialLengthChanged());
            L(end+1) = addlistener(obj.ControlsPanel, "CellIdChanged", ...
                @(~,~) obj.onCellIdChanged());

            % Editor panel signals.
            L(end+1) = addlistener(obj.OptoEditorPanel, "ConfigChanged", ...
                @(~,~) obj.onOptoConfigChanged());
            L(end+1) = addlistener(obj.CommandEditorPanel, "ConfigChanged", ...
                @(~,~) obj.onCommandConfigChanged());

            % Runner signals.
            L(end+1) = addlistener(obj.Runner, "TrialFinished", ...
                @(~,~) obj.onTrialFinished());
            L(end+1) = addlistener(obj.Runner, "StateChanged", ...
                @(~,~) obj.onRunnerStateChanged());
            L(end+1) = addlistener(obj.Runner, "AcquisitionError", ...
                @(~,~) obj.onAcquisitionError());

            % Telegraph signals.
            L(end+1) = addlistener(obj.Telegraph, "ModeChanged", ...
                @(~,~) obj.onModeChanged());
            L(end+1) = addlistener(obj.Telegraph, "GainChanged", ...
                @(~,~) obj.onGainChanged());

            obj.Listeners = L;
        end

        % --- ControlsPanel handlers -------------------------------------

        function onStartRequested(obj)
            if obj.Runner.state == "Idle"
                obj.Runner.start();
            end
        end

        function onStopRequested(obj)
            obj.Runner.stop();
        end

        function onItiChanged(obj)
            candidate = obj.Config;
            candidate.itiSec = obj.ControlsPanel.ItiSec;
            try
                obj.Runner.updateConfig(candidate);
            catch ME
                obj.ControlsPanel.setStatusText("Error: " + string(ME.message));
                return;
            end
            obj.Config = candidate;
            w = obj.stimulusWindowSec();
            obj.OptoEditorPanel.setStimulusWindowSec(w);
            obj.CommandEditorPanel.setStimulusWindowSec(w);
        end

        function onTrialLengthChanged(obj)
            newLen = obj.ControlsPanel.TrialLengthSec;
            if newLen < 0.301
                % Architecture §3 fixes a 300 ms preamble (baseline + seal-test
                % slot). A trial shorter than that has no stimulus window.
                obj.ControlsPanel.setStatusText( ...
                    "Error: trial length must be > 0.300 s (preamble).");
                obj.ControlsPanel.TrialLengthField.Value = obj.Config.trialLengthSec;
                return;
            end
            candidate = obj.Config;
            candidate.trialLengthSec = newLen;
            try
                obj.Runner.updateConfig(candidate);
            catch ME
                obj.ControlsPanel.setStatusText("Error: " + string(ME.message));
                obj.ControlsPanel.TrialLengthField.Value = obj.Config.trialLengthSec;
                return;
            end
            obj.Config = candidate;
            w = obj.stimulusWindowSec();
            obj.OptoEditorPanel.setStimulusWindowSec(w);
            obj.CommandEditorPanel.setStimulusWindowSec(w);
        end

        function onCellIdChanged(obj)
            candidate = obj.Config;
            candidate.cellId = obj.ControlsPanel.CellId;
            try
                obj.Runner.updateConfig(candidate);
            catch ME
                obj.ControlsPanel.setStatusText("Error: " + string(ME.message));
                return;
            end
            obj.Config = candidate;
        end

        % --- Editor handlers --------------------------------------------

        function onOptoConfigChanged(obj)
            candidate = obj.Config;
            optoCfg = obj.OptoEditorPanel.Config;
            % An nPulses==0 train means "no stim"; runner expects [] for that.
            if isfield(optoCfg, "nPulses") && optoCfg.nPulses <= 0
                candidate.opto = [];
            else
                candidate.opto = optoCfg;
            end
            try
                obj.Runner.updateConfig(candidate);
            catch ME
                obj.ControlsPanel.setStatusText("Error: " + string(ME.message));
                return;
            end
            obj.Config = candidate;
        end

        function onCommandConfigChanged(obj)
            candidate = obj.Config;
            cmdCfg = obj.CommandEditorPanel.Config;
            if isfield(cmdCfg, "nPulses") && cmdCfg.nPulses <= 0
                candidate.commandStim = [];
            else
                candidate.commandStim = cmdCfg;
            end
            try
                obj.Runner.updateConfig(candidate);
            catch ME
                obj.ControlsPanel.setStatusText("Error: " + string(ME.message));
                return;
            end
            obj.Config = candidate;
        end

        % --- Runner handlers --------------------------------------------

        function onTrialFinished(obj)
            r = obj.Runner.lastTrialResult;
            if isempty(fieldnames(r))
                return;
            end
            try
                obj.TrialPlotPanel.addTrial(r.aiCellUnits, r.sampleRateHz, r.mode);
            catch
            end
            try
                obj.TrendPlotsPanel.addTrialResult(r);
            catch
            end
            obj.ControlsPanel.setTrialCount(obj.Runner.trialCount);
        end

        function onRunnerStateChanged(obj)
            obj.ControlsPanel.setRunningState(obj.Runner.state);
            if obj.Runner.state == "Idle" && ~isempty(obj.Runner.lastError)
                obj.ControlsPanel.setStatusText( ...
                    "Error: " + string(obj.Runner.lastError.message));
            end
        end

        function onAcquisitionError(obj)
            err = obj.Runner.lastError;
            if ~isempty(err)
                obj.ControlsPanel.setStatusText("Error: " + string(err.message));
            end
        end

        % --- Telegraph handlers -----------------------------------------

        function onModeChanged(obj)
            m = obj.Telegraph.getMode();
            obj.ControlsPanel.setMode(m);
            obj.CommandEditorPanel.setMode(m);
            obj.TrialPlotPanel.setMode(m);
        end

        function onGainChanged(obj)
            obj.ControlsPanel.setGainDisplay(obj.Telegraph.getGain());
        end

        % --- Debug menu callbacks ---------------------------------------

        function onToggleMode(obj)
            currentMode = obj.Telegraph.getMode();
            if currentMode == "VC"
                obj.Telegraph.setMode("IC");
            else
                obj.Telegraph.setMode("VC");
            end
        end

        function onInjectGainChange(obj)
            g = obj.Telegraph.getGain();
            % Nudge the scaled VC gain so the listener fires.
            g.scaledVcPaPerV = g.scaledVcPaPerV * 1.01;
            obj.Telegraph.setGain(g);
        end

        % --- Helpers -----------------------------------------------------

        function w = stimulusWindowSec(obj)
            % Architecture §3: the stim window starts at 300 ms inside the trial.
            w = max(obj.Config.trialLengthSec - 0.3, eps);
        end
    end
end
