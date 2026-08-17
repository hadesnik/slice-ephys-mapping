classdef ControlsPanel < handle
    % ControlsPanel  Session-controls uipanel: Start/Stop, ITI, trial length,
    % cell ID, mode mirror, gain readout, status line.
    %
    % Built programmatically (no .mlapp). Owned by MainWindow; emits events
    % for user actions and exposes setters that MainWindow uses to push
    % runner / telegraph state down into the widgets.
    %
    % The mode label is read-only (claude.md invariant 3: the amplifier
    % owns the mode). The gain readout is whatever the telegraph last
    % reported; this panel does no unit math itself.
    %
    % Status-line composition: setRunningState latches the current state
    % string ("Idle" / "Running" / "Stopping"), setTrialCount latches the
    % count, and setStatusText overrides both with a free-form message
    % (used for AcquisitionError display). Whichever setter was called
    % last wins, except that state + count are re-rendered together so
    % calling setRunningState after a status override clears the error.
    %
    % Test access: button + edit-field handles are private but exposed to
    % the unittest framework via the Hidden ?matlab.unittest.TestCase block
    % so the test can drive their callbacks programmatically. The findall-
    % by-text pattern is also supported; the Hidden handles are belt and
    % suspenders.

    events
        StartRequested
        StopRequested
        ItiChanged
        TrialLengthChanged
        CellIdChanged
    end

    properties (SetAccess = private, GetAccess = public)
        Panel
        ItiSec          (1,1) double = 1.0
        TrialLengthSec  (1,1) double = 1.0
        CellId          (1,1) string = ""
    end

    properties (Hidden, Access = ?matlab.unittest.TestCase)
        StartButton
        StopButton
        ItiField
        TrialLengthField
        CellIdField
        ModeLabel
        StatusLabel
        GainLabel
    end

    properties (Access = private)
        CurrentState   (1,1) string = "Idle"
        CurrentCount   (1,1) uint32 = uint32(0)
        StatusOverride (1,1) string = ""
    end

    methods
        function obj = ControlsPanel(parent, initialConfig)
            arguments
                parent
                initialConfig (1,1) struct
            end

            obj.Panel = uipanel(parent, ...
                "Title", "Session controls", ...
                "FontSize", 12, ...
                "Units", "normalized", ...
                "Position", [0 0 1 1]);

            grid = uigridlayout(obj.Panel, [8 3]);
            grid.RowHeight   = {30, 24, 24, 24, 24, 24, 24, '1x'};
            grid.ColumnWidth = {110, 110, '1x'};
            grid.Padding     = [8 8 8 8];
            grid.RowSpacing  = 4;
            grid.ColumnSpacing = 6;

            obj.StartButton = uibutton(grid, "push", ...
                "Text", "Start", ...
                "FontSize", 12, ...
                "BackgroundColor", [0.30 0.69 0.31], ...
                "FontColor", [1 1 1], ...
                "FontWeight", "bold", ...
                "ButtonPushedFcn", @(s,e) obj.onStartPushed());
            obj.StartButton.Layout.Row = 1;
            obj.StartButton.Layout.Column = 1;

            obj.StopButton = uibutton(grid, "push", ...
                "Text", "Stop", ...
                "FontSize", 12, ...
                "Enable", "off", ...
                "BackgroundColor", [0.80 0.20 0.18], ...
                "FontColor", [1 1 1], ...
                "FontWeight", "bold", ...
                "ButtonPushedFcn", @(s,e) obj.onStopPushed());
            obj.StopButton.Layout.Row = 1;
            obj.StopButton.Layout.Column = 2;

            obj.addLabel(grid, "ITI (s)", 2, 1);
            itiInit = obj.readField(initialConfig, "itiSec", 1.0);
            obj.ItiField = uieditfield(grid, "numeric", ...
                "Value", itiInit, ...
                "Limits", [0 Inf], ...
                "FontSize", 12, ...
                "ValueChangedFcn", @(s,e) obj.onItiChanged(s));
            obj.ItiField.Layout.Row = 2;
            obj.ItiField.Layout.Column = 2;
            obj.ItiSec = itiInit;

            obj.addLabel(grid, "Trial length (s)", 3, 1);
            tlInit = obj.readField(initialConfig, "trialLengthSec", 1.0);
            obj.TrialLengthField = uieditfield(grid, "numeric", ...
                "Value", tlInit, ...
                "Limits", [eps Inf], ...
                "FontSize", 12, ...
                "ValueChangedFcn", @(s,e) obj.onTrialLengthChanged(s));
            obj.TrialLengthField.Layout.Row = 3;
            obj.TrialLengthField.Layout.Column = 2;
            obj.TrialLengthSec = tlInit;

            obj.addLabel(grid, "Cell ID", 4, 1);
            cellIdInit = obj.readField(initialConfig, "cellId", "");
            obj.CellIdField = uieditfield(grid, "text", ...
                "Value", char(cellIdInit), ...
                "FontSize", 12, ...
                "ValueChangedFcn", @(s,e) obj.onCellIdChanged(s));
            obj.CellIdField.Layout.Row = 4;
            obj.CellIdField.Layout.Column = 2;
            obj.CellId = string(cellIdInit);

            obj.addLabel(grid, "Mode", 5, 1);
            modeInit = obj.readField(initialConfig, "mode", "VC");
            obj.ModeLabel = uilabel(grid, ...
                "Text", char(modeInit), ...
                "FontSize", 12, ...
                "FontWeight", "bold");
            obj.ModeLabel.Layout.Row = 5;
            obj.ModeLabel.Layout.Column = [2 3];

            obj.addLabel(grid, "Gain", 6, 1);
            obj.GainLabel = uilabel(grid, ...
                "Text", "(gain not reported)", ...
                "FontSize", 11);
            obj.GainLabel.Layout.Row = 6;
            obj.GainLabel.Layout.Column = [2 3];

            obj.addLabel(grid, "Status", 7, 1);
            obj.StatusLabel = uilabel(grid, ...
                "Text", "Idle", ...
                "FontSize", 12);
            obj.StatusLabel.Layout.Row = 7;
            obj.StatusLabel.Layout.Column = [2 3];

            obj.renderStatus();
        end

        function setMode(obj, modeString)
            arguments
                obj
                modeString (1,1) string {mustBeMember(modeString, ["VC", "IC"])}
            end
            obj.ModeLabel.Text = char(modeString);
        end

        function setRunningState(obj, state)
            arguments
                obj
                state (1,1) string {mustBeMember(state, ["Idle", "Running", "Stopping"])}
            end
            obj.CurrentState   = state;
            obj.StatusOverride = "";
            switch state
                case "Idle"
                    obj.StartButton.Enable = "on";
                    obj.StopButton.Enable  = "off";
                case "Running"
                    obj.StartButton.Enable = "off";
                    obj.StopButton.Enable  = "on";
                case "Stopping"
                    obj.StartButton.Enable = "off";
                    obj.StopButton.Enable  = "off";
            end
            obj.renderStatus();
        end

        function setTrialCount(obj, n)
            arguments
                obj
                n (1,1) {mustBeNonnegative, mustBeInteger}
            end
            obj.CurrentCount = uint32(n);
            obj.renderStatus();
        end

        function setGainDisplay(obj, gainStruct)
            arguments
                obj
                gainStruct (1,1) struct
            end
            txt = sprintf( ...
                "VC:%g pA/V  IC:%g mV/mV  (cmd VC:%g mV/V, IC:%g pA/V)", ...
                gainStruct.scaledVcPaPerV, ...
                gainStruct.scaledIcMvPerMv, ...
                gainStruct.commandVcMvPerV, ...
                gainStruct.commandIcPaPerV);
            obj.GainLabel.Text = char(txt);
        end

        function setStatusText(obj, text)
            arguments
                obj
                text (1,1) string
            end
            obj.StatusOverride = text;
            obj.StatusLabel.Text = char(text);
        end
    end

    methods (Access = private)
        function onStartPushed(obj)
            notify(obj, "StartRequested");
        end

        function onStopPushed(obj)
            notify(obj, "StopRequested");
        end

        function onItiChanged(obj, src)
            obj.ItiSec = double(src.Value);
            notify(obj, "ItiChanged");
        end

        function onTrialLengthChanged(obj, src)
            obj.TrialLengthSec = double(src.Value);
            notify(obj, "TrialLengthChanged");
        end

        function onCellIdChanged(obj, src)
            obj.CellId = string(src.Value);
            notify(obj, "CellIdChanged");
        end

        function renderStatus(obj)
            if strlength(obj.StatusOverride) > 0
                obj.StatusLabel.Text = char(obj.StatusOverride);
                return;
            end
            switch obj.CurrentState
                case "Running"
                    txt = sprintf("Running - %d trials", obj.CurrentCount);
                case "Stopping"
                    txt = sprintf("Stopping - %d trials", obj.CurrentCount);
                otherwise
                    txt = sprintf("Idle - %d trials", obj.CurrentCount);
            end
            obj.StatusLabel.Text = char(txt);
        end
    end

    methods (Static, Access = private)
        function addLabel(parent, text, row, col)
            lbl = uilabel(parent, "Text", text, "FontSize", 12);
            lbl.Layout.Row = row;
            lbl.Layout.Column = col;
        end

        function v = readField(s, name, default)
            if isfield(s, name) && ~isempty(s.(name))
                v = s.(name);
            else
                v = default;
            end
        end
    end
end
