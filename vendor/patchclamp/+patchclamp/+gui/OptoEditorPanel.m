classdef OptoEditorPanel < handle
    % OptoEditorPanel  Editor for the optogenetic LED pulse train (AO2).
    %
    % Amplitude is in % brightness (0..100). Internally the preview goes
    % through PulseTrain.build with amplitudeUnit "percent", which validates
    % via LedDriver so the 0..100 range is enforced in one place.

    properties (Constant, Access = private)
        SAMPLE_RATE_HZ = 20000
        DEFAULT_WINDOW_SEC = 0.7
    end

    properties (SetAccess = private, GetAccess = public)
        Panel
        Config struct
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
        % OptoUpdated is the spec event for Round 3a Agent H: parent app
        % subscribes and pulls the latest struct via currentConfig().
        ConfigChanged
        OptoUpdated
    end

    methods
        function obj = OptoEditorPanel(parent)
            arguments
                parent
            end

            obj.Config = patchclamp.config.PulseTrainConfig.defaultConfig();
            obj.stimulusWindowSec = obj.DEFAULT_WINDOW_SEC;

            obj.Panel = uipanel(parent, ...
                'Title', 'Optogenetic stim (LED, AO2)', ...
                'Tag', 'optoEditorPanel');

            grid = uigridlayout(obj.Panel, [7, 3]);
            grid.RowHeight = {22, 22, 22, 22, 26, 18, '1x'};
            grid.ColumnWidth = {'fit', 90, '1x'};

            % Row 1: pulse duration
            lbl1 = uilabel(grid, 'Text', 'Pulse duration (ms)');
            lbl1.Layout.Row = 1; lbl1.Layout.Column = 1;
            obj.pulseDurationField = uieditfield(grid, 'numeric', ...
                'Tag', 'pulseDurationField', ...
                'Value', obj.Config.pulseDurationMs);
            obj.pulseDurationField.Layout.Row = 1; obj.pulseDurationField.Layout.Column = 2;

            % Row 2: amplitude (% brightness)
            obj.amplitudeLabel = uilabel(grid, ...
                'Text', 'Amplitude (% brightness)', ...
                'Tag', 'amplitudeLabel');
            obj.amplitudeLabel.Layout.Row = 2; obj.amplitudeLabel.Layout.Column = 1;
            obj.amplitudeField = uieditfield(grid, 'numeric', ...
                'Tag', 'amplitudeField', ...
                'Value', obj.Config.amplitude);
            obj.amplitudeField.Layout.Row = 2; obj.amplitudeField.Layout.Column = 2;

            % Row 3: frequency
            lbl3 = uilabel(grid, 'Text', 'Frequency (Hz)');
            lbl3.Layout.Row = 3; lbl3.Layout.Column = 1;
            obj.frequencyField = uieditfield(grid, 'numeric', ...
                'Tag', 'frequencyField', ...
                'Value', obj.Config.frequencyHz);
            obj.frequencyField.Layout.Row = 3; obj.frequencyField.Layout.Column = 2;

            % Row 4: number of pulses
            lbl4 = uilabel(grid, 'Text', 'Number of pulses');
            lbl4.Layout.Row = 4; lbl4.Layout.Column = 1;
            obj.nPulsesField = uieditfield(grid, 'numeric', ...
                'Tag', 'nPulsesField', ...
                'RoundFractionalValues', 'on', ...
                'Value', obj.Config.nPulses);
            obj.nPulsesField.Layout.Row = 4; obj.nPulsesField.Layout.Column = 2;

            % Row 5: buttons (Update + Clear in a sub-layout)
            buttonRow = uigridlayout(grid, [1, 2]);
            buttonRow.Layout.Row = 5; buttonRow.Layout.Column = [1 3];
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

            % Row 6: status label
            obj.statusLabel = uilabel(grid, ...
                'Text', '', ...
                'Tag', 'statusLabel', ...
                'FontColor', [0.7 0 0]);
            obj.statusLabel.Layout.Row = 6; obj.statusLabel.Layout.Column = [1 3];

            % Row 7: preview axes
            obj.previewAxes = uiaxes(grid, 'Tag', 'previewAxes');
            obj.previewAxes.Layout.Row = 7; obj.previewAxes.Layout.Column = [1 3];
            % Simpler than dual-axis ticks (Q7): show % on the Y axis and the
            % full-scale volts equivalent in the title, so the user can sanity-
            % check what the LED driver actually sees.
            ledMaxV = patchclamp.hardware.LedDriver.MAX_VOLTS;
            title(obj.previewAxes, sprintf('Preview (100%% = %.1f V at LED driver)', ledMaxV));
            xlabel(obj.previewAxes, 'Time (ms)');
            ylabel(obj.previewAxes, 'Brightness (%)');

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
            % Returns the last successfully-validated PulseTrainConfig struct
            % (units = "percent" for the LED amplitude).
            cfg = obj.Config;
        end
    end

    methods (Access = private)
        function onUpdate(obj)
            candidate = obj.readFields();
            try
                patchclamp.config.PulseTrainConfig.validate(candidate);
                patchclamp.config.PulseTrainConfig.validateFitsWindow(candidate, obj.stimulusWindowSec);
                % LedDriver enforces 0..100 for opto amplitudes; do the conversion
                % round-trip to surface a clear error if the user typed 150.
                patchclamp.hardware.LedDriver.brightnessPercentToVolts(candidate.amplitude);
            catch ME
                obj.statusLabel.Text = ME.message;
                obj.showAlert(ME.message);
                return;
            end

            obj.statusLabel.Text = '';
            obj.Config = candidate;
            obj.renderPreview();
            notify(obj, 'ConfigChanged');
            notify(obj, 'OptoUpdated');
        end

        function showAlert(obj, msg)
            f = ancestor(obj.Panel, 'figure');
            if ~isempty(f) && isvalid(f) && isa(f, 'matlab.ui.Figure')
                try
                    uialert(f, char(msg), 'Invalid opto pulse train');
                catch
                end
            end
        end

        function onClear(obj)
            % Clear sets nPulses=0 and amplitude=0 so the stim is effectively off.
            % This bypasses PulseTrainConfig.validate (which requires nPulses > 0)
            % on purpose: an empty train is a valid "no stim" state for the runner
            % to detect and skip.
            cleared = obj.Config;
            cleared.amplitude = 0;
            cleared.nPulses = 0;
            obj.Config = cleared;

            obj.amplitudeField.Value = 0;
            obj.nPulsesField.Value = 0;

            obj.statusLabel.Text = '';
            cla(obj.previewAxes);
            notify(obj, 'ConfigChanged');
            notify(obj, 'OptoUpdated');
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
            try
                [wf, ~] = patchclamp.protocol.PulseTrain.build( ...
                    obj.Config, obj.SAMPLE_RATE_HZ, obj.stimulusWindowSec, "percent");
                % Convert back to % brightness for the display axis.
                wfPct = wf * (100 / patchclamp.hardware.LedDriver.MAX_VOLTS);
                t = (0:numel(wfPct)-1).' * (1000 / obj.SAMPLE_RATE_HZ);
                plot(obj.previewAxes, t, wfPct, 'LineWidth', 1.0);
                xlim(obj.previewAxes, [0, obj.stimulusWindowSec * 1000]);
            catch
                % Bad config (shouldn't happen post-validate) — show empty axes.
            end
        end
    end
end
