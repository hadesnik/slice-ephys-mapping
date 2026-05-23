classdef CommandEditorPanel < handle
    % CommandEditorPanel  Editor for the command-side pulse train (AO0).
    %
    % The amplitude label and preview Y-label are mode-driven (auto-mode Q3 -> A3):
    %   VC -> "Amplitude (mV)"
    %   IC -> "Amplitude (pA)"
    % The amplitude *value* is preserved across mode flips; the user is responsible
    % for re-entering a sensible number for the new mode.

    properties (Constant, Access = private)
        SAMPLE_RATE_HZ = 20000
        DEFAULT_WINDOW_SEC = 0.7
    end

    properties (SetAccess = private, GetAccess = public)
        Panel
        Config struct
        Mode (1,1) string = "VC"
    end

    properties (Access = private)
        stimulusWindowSec double = 0.7
        pulseDurationField
        amplitudeField
        frequencyField
        nPulsesField
        updateButton
        clearButton
        statusLabel
        amplitudeLabel
        previewAxes
    end

    events
        % ConfigChanged is the legacy broadcast (kept for backwards compat).
        % CommandUpdated is the spec event for Round 3a Agent H: parent app
        % subscribes and pulls the latest struct via currentConfig().
        ConfigChanged
        CommandUpdated
    end

    methods
        function obj = CommandEditorPanel(parent)
            arguments
                parent
            end

            obj.Config = patchclamp.config.PulseTrainConfig.defaultConfig();
            obj.stimulusWindowSec = obj.DEFAULT_WINDOW_SEC;
            obj.Mode = "VC";

            obj.Panel = uipanel(parent, ...
                'Title', 'Command stim (AO0, mode-aware)', ...
                'Tag', 'commandEditorPanel');

            grid = uigridlayout(obj.Panel, [7, 2]);
            grid.RowHeight = {22, 22, 22, 22, 26, 18, '1x'};
            grid.ColumnWidth = {'fit', '1x'};

            lbl1 = uilabel(grid, 'Text', 'Pulse duration (ms)');
            lbl1.Layout.Row = 1; lbl1.Layout.Column = 1;
            obj.pulseDurationField = uieditfield(grid, 'numeric', ...
                'Tag', 'pulseDurationField', ...
                'Value', obj.Config.pulseDurationMs);
            obj.pulseDurationField.Layout.Row = 1; obj.pulseDurationField.Layout.Column = 2;

            obj.amplitudeLabel = uilabel(grid, ...
                'Text', obj.amplitudeLabelTextForMode(obj.Mode), ...
                'Tag', 'amplitudeLabel');
            obj.amplitudeLabel.Layout.Row = 2; obj.amplitudeLabel.Layout.Column = 1;
            obj.amplitudeField = uieditfield(grid, 'numeric', ...
                'Tag', 'amplitudeField', ...
                'Value', obj.Config.amplitude);
            obj.amplitudeField.Layout.Row = 2; obj.amplitudeField.Layout.Column = 2;

            lbl3 = uilabel(grid, 'Text', 'Frequency (Hz)');
            lbl3.Layout.Row = 3; lbl3.Layout.Column = 1;
            obj.frequencyField = uieditfield(grid, 'numeric', ...
                'Tag', 'frequencyField', ...
                'Value', obj.Config.frequencyHz);
            obj.frequencyField.Layout.Row = 3; obj.frequencyField.Layout.Column = 2;

            lbl4 = uilabel(grid, 'Text', 'Number of pulses');
            lbl4.Layout.Row = 4; lbl4.Layout.Column = 1;
            obj.nPulsesField = uieditfield(grid, 'numeric', ...
                'Tag', 'nPulsesField', ...
                'RoundFractionalValues', 'on', ...
                'Value', obj.Config.nPulses);
            obj.nPulsesField.Layout.Row = 4; obj.nPulsesField.Layout.Column = 2;

            buttonRow = uigridlayout(grid, [1, 2]);
            buttonRow.Layout.Row = 5; buttonRow.Layout.Column = [1 2];
            buttonRow.ColumnWidth = {'1x', '1x'};
            buttonRow.Padding = [0 0 0 0];
            obj.updateButton = uibutton(buttonRow, 'push', ...
                'Text', 'Update', ...
                'Tag', 'updateButton', ...
                'ButtonPushedFcn', @(~,~) obj.onUpdate());
            obj.clearButton = uibutton(buttonRow, 'push', ...
                'Text', 'Clear', ...
                'Tag', 'clearButton', ...
                'ButtonPushedFcn', @(~,~) obj.onClear());

            obj.statusLabel = uilabel(grid, ...
                'Text', '', ...
                'Tag', 'statusLabel', ...
                'FontColor', [0.7 0 0]);
            obj.statusLabel.Layout.Row = 6; obj.statusLabel.Layout.Column = [1 2];

            obj.previewAxes = uiaxes(grid, 'Tag', 'previewAxes');
            obj.previewAxes.Layout.Row = 7; obj.previewAxes.Layout.Column = [1 2];
            title(obj.previewAxes, 'Preview');
            xlabel(obj.previewAxes, 'Time (ms)');
            ylabel(obj.previewAxes, obj.previewYLabelForMode(obj.Mode));

            obj.renderPreview();
        end

        function setMode(obj, modeString)
            arguments
                obj
                modeString (1,1) string {mustBeMember(modeString, ["VC", "IC"])}
            end
            obj.Mode = modeString;
            obj.amplitudeLabel.Text = obj.amplitudeLabelTextForMode(modeString);
            ylabel(obj.previewAxes, obj.previewYLabelForMode(modeString));
            obj.renderPreview();
        end

        function setStimulusWindowSec(obj, windowSec)
            arguments
                obj
                windowSec (1,1) double {mustBePositive}
            end
            obj.stimulusWindowSec = windowSec;
            obj.renderPreview();
        end

        function cfg = currentConfig(obj)
            % Returns the last successfully-validated PulseTrainConfig struct.
            cfg = obj.Config;
        end
    end

    methods (Access = private, Static)
        function s = amplitudeLabelTextForMode(modeString)
            if modeString == "VC"
                s = 'Amplitude (mV)';
            else
                s = 'Amplitude (pA)';
            end
        end

        function s = previewYLabelForMode(modeString)
            if modeString == "VC"
                s = 'Command (mV)';
            else
                s = 'Command (pA)';
            end
        end
    end

    methods (Access = private)
        function onUpdate(obj)
            candidate = obj.readFields();
            try
                patchclamp.config.PulseTrainConfig.validate(candidate);
                patchclamp.config.PulseTrainConfig.validateFitsWindow(candidate, obj.stimulusWindowSec);
            catch ME
                obj.statusLabel.Text = ME.message;
                obj.showAlert(ME.message);
                return;
            end

            obj.statusLabel.Text = '';
            obj.Config = candidate;
            obj.renderPreview();
            notify(obj, 'ConfigChanged');
            notify(obj, 'CommandUpdated');
        end

        function showAlert(obj, msg)
            % uialert needs a uifigure ancestor; if there is none (panel built
            % under a regular figure or detached parent), fall back silently to
            % the inline statusLabel so we never throw from a UI callback.
            f = ancestor(obj.Panel, 'figure');
            if ~isempty(f) && isvalid(f) && isa(f, 'matlab.ui.Figure')
                try
                    uialert(f, char(msg), 'Invalid command pulse train');
                catch
                end
            end
        end

        function onClear(obj)
            cleared = obj.Config;
            cleared.amplitude = 0;
            cleared.nPulses = 0;
            obj.Config = cleared;

            obj.amplitudeField.Value = 0;
            obj.nPulsesField.Value = 0;

            obj.statusLabel.Text = '';
            cla(obj.previewAxes);
            notify(obj, 'ConfigChanged');
            notify(obj, 'CommandUpdated');
        end

        function s = readFields(obj)
            s = struct( ...
                'pulseDurationMs', obj.pulseDurationField.Value, ...
                'amplitude',       obj.amplitudeField.Value, ...
                'frequencyHz',     obj.frequencyField.Value, ...
                'nPulses',         obj.nPulsesField.Value);
        end

        function renderPreview(obj)
            cla(obj.previewAxes);
            if obj.Config.nPulses <= 0
                return;
            end
            try
                unitStr = obj.amplitudeUnitForMode(obj.Mode);
                [wf, ~] = patchclamp.protocol.PulseTrain.build( ...
                    obj.Config, obj.SAMPLE_RATE_HZ, obj.stimulusWindowSec, unitStr);
                t = (0:numel(wf)-1).' * (1000 / obj.SAMPLE_RATE_HZ);
                plot(obj.previewAxes, t, wf, 'LineWidth', 1.0);
                xlim(obj.previewAxes, [0, obj.stimulusWindowSec * 1000]);
            catch
            end
        end
    end

    methods (Access = private, Static)
        function u = amplitudeUnitForMode(modeString)
            if modeString == "VC"
                u = "mV";
            else
                u = "pA";
            end
        end
    end
end
