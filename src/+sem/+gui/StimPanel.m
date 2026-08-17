classdef StimPanel < handle
    %StimPanel One stimulus channel: parameters, Update, and its preview.
    %
    %   Serves both stimulus panels of the acquisition window — the light
    %   source and the cell command — because in the legacy GUI they are the
    %   same control set over the same pulse-train grammar, differing only in
    %   labels and units.
    %
    %   Contract carried over from the legacy GUI: editing a field does NOT
    %   change the stimulus. You press Update, the preview redraws immediately,
    %   and the next sweep delivers it. That separation is what lets the
    %   experimenter dial in a value mid-run without the half-typed number
    %   reaching the cell.
    %
    %   Fires `Updated` when Update is pressed and the parameters validate;
    %   listeners read `spec` and `stepSpec` off the panel.
    %
    %   See also sem.protocol.pulseTrain, sem.gui.AcqWindow.

    properties (SetAccess = private, GetAccess = public)
        Panel
        PreviewAxes
        Channel  (1,:) char = 'command'   % 'command' | 'led'
    end

    properties (Access = private, Hidden)
        AmpField
        DurField
        NumField
        FreqField
        StartField
        DeltaField
        StepParamDrop
        StepCheck
        AmpLabel
        StatusLabel
        PreviewLine
        AmpUnit (1,:) char = 'V'
    end

    events
        Updated
    end

    methods
        function obj = StimPanel(parent, opts)
            %StimPanel Build into parent.
            %   opts: Title, Channel, AmplitudeUnit, DeltaLabel, UpdateLabel,
            %         Defaults (a pulseTrain spec), StepParameters (cellstr)
            arguments
                parent
                opts.Title (1,:) char = 'Stimulus'
                opts.Channel (1,:) char = 'command'
                opts.AmplitudeUnit (1,:) char = 'V'
                opts.DeltaLabel (1,:) char = 'delta per sweep'
                opts.UpdateLabel (1,:) char = 'Update'
                opts.Defaults struct = struct()
                opts.StepParameters cell = {'amplitude', 'pulse duration', ...
                                            'number of pulses', 'frequency'}
            end

            obj.Channel = opts.Channel;
            obj.AmpUnit = opts.AmplitudeUnit;
            d = opts.Defaults;

            obj.Panel = uipanel(parent, 'Title', opts.Title, ...
                'FontWeight', 'bold');
            outer = uigridlayout(obj.Panel, [2 1]);
            outer.RowHeight = {'fit', '1x'};
            outer.ColumnWidth = {'1x'};
            outer.Padding = [4 4 4 4];
            outer.RowSpacing = 4;

            % --- parameter rows ------------------------------------------
            g = uigridlayout(outer, [8 2]);
            g.Layout.Row = 1;
            g.RowHeight = repmat({24}, 1, 8);
            g.ColumnWidth = {'1.35x', '1x'};
            g.Padding = [0 0 0 0];
            g.RowSpacing = 2;

            obj.AmpLabel = uilabel(g, 'Text', obj.ampLabelText());
            obj.AmpField = uieditfield(g, 'numeric', ...
                'Value', getf(d, 'amplitude', 0));

            uilabel(g, 'Text', 'pulse duration (ms)');
            obj.DurField = uieditfield(g, 'numeric', 'Limits', [0 Inf], ...
                'Value', getf(d, 'pulseDurationMs', 5));

            uilabel(g, 'Text', 'number of pulses');
            obj.NumField = uieditfield(g, 'numeric', 'Limits', [0 Inf], ...
                'RoundFractionalValues', 'on', ...
                'Value', getf(d, 'nPulses', 1));

            uilabel(g, 'Text', 'frequency (Hz)');
            obj.FreqField = uieditfield(g, 'numeric', 'Limits', [0 Inf], ...
                'Value', getf(d, 'frequencyHz', 10));

            uilabel(g, 'Text', 'start time (ms)');
            obj.StartField = uieditfield(g, 'numeric', 'Limits', [0 Inf], ...
                'Value', getf(d, 'startTimeMs', 0));

            uilabel(g, 'Text', opts.DeltaLabel);
            obj.DeltaField = uieditfield(g, 'numeric', ...
                'Value', getf(d, 'amplitudeDeltaPerSweep', 0));

            uilabel(g, 'Text', 'step parameter');
            obj.StepParamDrop = uidropdown(g, 'Items', opts.StepParameters, ...
                'Value', opts.StepParameters{1});

            obj.StepCheck = uicheckbox(g, 'Text', 'step each sweep', 'Value', false);
            b = uibutton(g, 'Text', opts.UpdateLabel, ...
                'ButtonPushedFcn', @(~, ~) obj.onUpdate());
            b.FontWeight = 'bold';

            % --- preview --------------------------------------------------
            % The axes is nested in a panel with a normalized position: a
            % uiaxes placed straight into a uigridlayout row escapes the row.
            axHost = uipanel(outer, 'BorderType', 'none');
            axHost.Layout.Row = 2;
            obj.PreviewAxes = uiaxes(axHost, 'Units', 'normalized', ...
                'Position', [0 0 1 1]);
            obj.PreviewAxes.FontSize = 8;
            xlabel(obj.PreviewAxes, 'seconds');
            ylabel(obj.PreviewAxes, obj.AmpUnit);
            title(obj.PreviewAxes, 'next sweep');

            obj.StatusLabel = uilabel(g, 'Text', '');
            obj.StatusLabel.Layout.Row = 8;
            obj.StatusLabel.Layout.Column = 1;
        end

        function s = spec(obj)
            %spec The pulse-train spec these fields describe.
            s = struct( ...
                'startTimeMs',     obj.StartField.Value, ...
                'nPulses',         obj.NumField.Value, ...
                'pulseDurationMs', obj.DurField.Value, ...
                'amplitude',       obj.AmpField.Value, ...
                'frequencyHz',     max(obj.FreqField.Value, eps));
        end

        function s = stepSpec(obj)
            %stepSpec The per-sweep stepping request, or [] when disabled.
            if ~obj.StepCheck.Value || obj.DeltaField.Value == 0
                s = [];
                return
            end
            map = struct('amplitude', 'amplitude', ...
                'pulse_duration', 'durationMs', ...
                'number_of_pulses', 'nPulses', ...
                'frequency', 'frequencyHz');
            key = strrep(obj.StepParamDrop.Value, ' ', '_');
            if ~isfield(map, key)
                s = [];
                return
            end
            s = struct('channel', obj.Channel, 'parameter', map.(key), ...
                'delta', obj.DeltaField.Value);
        end

        function setSpec(obj, s)
            %setSpec Write values back into the fields.
            %   Used after a stepped sweep so the panel shows what is actually
            %   being delivered, rather than the value first typed.
            obj.AmpField.Value   = getf(s, 'amplitude', obj.AmpField.Value);
            obj.DurField.Value   = getf(s, 'pulseDurationMs', obj.DurField.Value);
            obj.NumField.Value   = getf(s, 'nPulses', obj.NumField.Value);
            obj.FreqField.Value  = getf(s, 'frequencyHz', obj.FreqField.Value);
            obj.StartField.Value = getf(s, 'startTimeMs', obj.StartField.Value);
        end

        function setAmplitudeUnit(obj, unit)
            %setAmplitudeUnit Relabel on a clamp-mode change (pA <-> mV).
            obj.AmpUnit = char(unit);
            obj.AmpLabel.Text = obj.ampLabelText();
            ylabel(obj.PreviewAxes, obj.AmpUnit);
        end

        function drawPreview(obj, t, wave)
            %drawPreview Show the waveform the next sweep will deliver.
            if isempty(obj.PreviewLine) || ~isvalid(obj.PreviewLine)
                obj.PreviewLine = plot(obj.PreviewAxes, t, wave, 'LineWidth', 1);
            else
                set(obj.PreviewLine, 'XData', t, 'YData', wave);
            end
            if ~isempty(t)
                xlim(obj.PreviewAxes, [t(1), t(end)]);
            end
            pad = max(abs(wave)) * 0.15 + eps;
            ylim(obj.PreviewAxes, [min(wave) - pad, max(wave) + pad]);
        end

        function pressUpdate(obj)
            %pressUpdate Commit the current fields, as the Update button does.
            %   Public so a protocol can be applied programmatically and so
            %   tests can exercise the commit path rather than reaching into
            %   widget handles.
            obj.onUpdate();
        end

        function setStepping(obj, parameterLabel, delta, enabled)
            %setStepping Configure per-sweep stepping without the mouse.
            obj.StepParamDrop.Value = parameterLabel;
            obj.DeltaField.Value = delta;
            obj.StepCheck.Value = logical(enabled);
        end

        function setStatus(obj, txt)
            obj.StatusLabel.Text = char(txt);
        end
    end

    methods (Access = private)
        function txt = ampLabelText(obj)
            txt = sprintf('pulse amplitude (%s)', obj.AmpUnit);
        end

        function onUpdate(obj)
            try
                s = obj.spec();
                if s.nPulses > 0 && s.pulseDurationMs <= 0
                    error('sem:gui:StimPanel:badDuration', ...
                        'Pulse duration must be greater than 0.');
                end
                obj.setStatus('');
                notify(obj, 'Updated');
            catch ME
                obj.setStatus(ME.message);
            end
        end
    end
end

function v = getf(s, name, default)
if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
    v = s.(name);
else
    v = default;
end
end
