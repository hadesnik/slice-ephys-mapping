classdef AcqWindow < handle
    %AcqWindow Single-cell patch-clamp acquisition window.
    %
    %   A rebuild of the lab's legacy Acq GUI (kept for reference under
    %   docs/old patch clamp GUI scripts/) on a modern uifigure and this repo's
    %   backend, for one patched cell instead of two.
    %
    %   Layout, following the original:
    %     top strip   Start / Stop / Pause, ISI, sweep duration, clamp mode,
    %                 TestPulse, sweep counter and elapsed time, save path and
    %                 experiment name, Seal test, F/I family, Mapping
    %     left        live sweep trace, then Rs / holding / input-resistance
    %                 trend strips vs experiment time, then the sweep browser
    %     centre      light-source and cell-command stimulus panels, each with
    %                 its own Update button and preview
    %     right       experiment metadata
    %
    %   Behaviours carried over deliberately: every control stays live during
    %   acquisition (the experimenter does change parameters mid-run); an edit
    %   takes effect on the next sweep, never the one in flight; saturated
    %   colours mark the run controls; the preview shows the next sweep.
    %
    %   Improvement on the original: the three trend strips carry numeric
    %   readouts in their titles. The legacy GUI showed Rs and Rin only as
    %   trend plots, with numbers available solely in a separate seal-test
    %   window — which is why sealing needed that second window at all.
    %
    %   See also sem.acq.SweepRunner, sem.gui.StimPanel, sem.gui.MappingWindow.

    properties (SetAccess = private, GetAccess = public)
        Figure
        Config          % sem config struct
        Runner          % sem.acq.SweepRunner
        Daq             % underlying tfp.hardware.DAQ
        Dmd
        Telegraph
        Adapter         % sem.hardware.PatchDaqAdapter
        LedPanel        % sem.gui.StimPanel
        CommandPanel    % sem.gui.StimPanel
        SessionDir
        Targets = []
        Model = []
        MappingWindow = []
    end

    properties (Access = private)
        % run controls
        StartBtn; StopBtn; PauseBtn
        IsiField; DurField; ModeDrop; TestPulseCheck
        SweepLabel; TimeLabel; StatusLabel
        SavePathField; ExpNameField; SaveEachCheck
        SealBtn; FiBtn

        % display
        LiveAxes; LivePanel; LiveLine
        RsAxes; RsPanel; RsLine
        IhAxes; IhPanel; IhLine
        IrAxes; IrPanel; IrLine
        BrowseAxes; BrowsePanel; BrowseField
        HoldLimitsCheck; HoldPlotCheck

        % metadata
        MetaFields = struct()

        Listeners = event.listener.empty(1, 0)
        Sweeps = {}          % stored sweeps for the browser
        BrowseIdx = 0
        IsShutdown (1,1) logical = false
        OwnsRig (1,1) logical = true
    end

    methods
        function obj = AcqWindow(configOrPath, options)
            arguments
                configOrPath = fullfile(sem.gui.AcqWindow.repoRoot(), 'configs', 'mock.yaml')
                options.SessionDir = ''
                options.Visible (1,1) string = "on"
                options.Rig = []          % {dmd, daq} to reuse instead of building
            end

            obj.Config = sem.gui.AcqWindow.resolveConfig(configOrPath);

            if isempty(options.Rig)
                [obj.Dmd, obj.Daq] = sem.hardware.makeRig(obj.Config);
                obj.OwnsRig = true;
                if strcmpi(sem.util.configField(obj.Config, 'hardwareKind', 'mock'), 'mock')
                    obj.attachSimulatedCells();
                end
            else
                obj.Dmd = options.Rig{1};
                obj.Daq = options.Rig{2};
                obj.OwnsRig = false;
            end

            obj.SessionDir = char(options.SessionDir);
            if isempty(obj.SessionDir)
                dataDir = sem.util.configField( ...
                    sem.util.configField(obj.Config, 'paths', struct()), 'dataDir', tempdir());
                obj.SessionDir = fullfile(dataDir, ...
                    ['acq_' datestr(now, 'yyyymmdd_HHMMSS')]); %#ok<TNOW1,DATST>
            end
            if ~isfolder(obj.SessionDir)
                mkdir(obj.SessionDir);
            end

            obj.Telegraph = sem.hardware.ConfigTelegraph(obj.Config, 'VC');
            obj.Adapter = sem.hardware.PatchDaqAdapter(obj.Daq, obj.Config, obj.Telegraph);
            obj.Runner = sem.acq.SweepRunner(obj.Adapter, obj.Telegraph, ...
                sem.gui.AcqWindow.sweepConfigFrom(obj.Config), obj.SessionDir);
            obj.Runner.saveFcn = @(s) obj.onSaveSweep(s);

            obj.build(options.Visible);
            obj.wire();
            obj.pushConfigToRunner();
            obj.refreshPreviews();
            obj.setStatus('Idle');
        end

        function setClampMode(obj, mode)
            %setClampMode Switch clamp mode as the dropdown does.
            if strcmpi(char(mode), 'IC')
                obj.ModeDrop.Value = 'Current Clamp';
            else
                obj.ModeDrop.Value = 'Voltage Clamp';
            end
            obj.onModeChanged();
        end

        function setSealMode(obj, tf)
            %setSealMode Enter or leave the inline seal test.
            obj.SealBtn.Value = logical(tf);
            obj.onSealMode(obj.SealBtn.Value);
        end

        function browseStep(obj, d)
            %browseStep Move the sweep browser by d sweeps.
            obj.stepBrowse(d);
        end

        function openMapping(obj)
            %openMapping Launch the mapping window, as the Mapping button does.
            obj.onMapping();
        end

        function d = sweepDir(obj)
            %sweepDir Where this session's sweeps are written.
            d = fullfile(obj.SavePathField.Value, obj.ExpNameField.Value);
        end

        function shutdown(obj)
            if obj.IsShutdown
                return
            end
            obj.IsShutdown = true;
            for k = 1:numel(obj.Listeners)
                try, delete(obj.Listeners(k)); catch, end
            end
            obj.Listeners = event.listener.empty(1, 0);
            try, obj.Runner.stop(); catch, end
            try
                if ~isempty(obj.MappingWindow) && isvalid(obj.MappingWindow)
                    obj.MappingWindow.shutdown();
                end
            catch
            end
            try, obj.Adapter.cleanup(); catch, end
            try
                if obj.OwnsRig && ~isempty(obj.Daq) && isvalid(obj.Daq)
                    obj.Daq.cleanup();
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

    % ---------------------------------------------------------------- build
    methods (Access = private)

        function build(obj, visible)
            obj.Figure = uifigure('Name', 'Acq — slice patch clamp', ...
                'Position', [40 40 1680 980], 'Visible', visible);
            root = uigridlayout(obj.Figure, [2 1]);
            root.RowHeight = {74, '1x'};
            root.ColumnWidth = {'1x'};
            root.Padding = [6 6 6 6];
            root.RowSpacing = 6;

            obj.buildTopStrip(root);

            body = uigridlayout(root, [1 3]);
            body.Layout.Row = 2;
            body.ColumnWidth = {'1.5x', 340, 210};
            body.Padding = [0 0 0 0];
            body.ColumnSpacing = 6;

            obj.buildWatchColumn(body);
            obj.buildStimColumn(body);
            obj.buildMetaColumn(body);

            obj.Figure.CloseRequestFcn = @(~, ~) obj.shutdown();
        end

        function buildTopStrip(obj, root)
            strip = uipanel(root, 'BorderType', 'none');
            strip.Layout.Row = 1;
            g = uigridlayout(strip, [2 14]);
            g.RowHeight = {30, 26};
            g.ColumnWidth = {70, 70, 70, 40, 60, 60, 60, 90, 110, 80, 90, 90, 90, '1x'};
            g.Padding = [0 0 0 0];
            g.ColumnSpacing = 4;
            g.RowSpacing = 4;

            obj.StartBtn = uibutton(g, 'Text', 'Start', 'FontWeight', 'bold', ...
                'BackgroundColor', [0.30 0.80 0.30], ...
                'ButtonPushedFcn', @(~, ~) obj.onStart());
            obj.StartBtn.Layout.Row = 1; obj.StartBtn.Layout.Column = 1;

            obj.StopBtn = uibutton(g, 'Text', 'Stop', 'FontWeight', 'bold', ...
                'BackgroundColor', [0.90 0.35 0.30], 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) obj.onStop());
            obj.StopBtn.Layout.Row = 1; obj.StopBtn.Layout.Column = 2;

            obj.PauseBtn = uibutton(g, 'state', 'Text', 'Pause', ...
                'BackgroundColor', [0.98 0.75 0.40], 'Enable', 'off', ...
                'ValueChangedFcn', @(s, ~) obj.onPause(s.Value));
            obj.PauseBtn.Layout.Row = 1; obj.PauseBtn.Layout.Column = 3;

            % Seed from the runner's config so the rig YAML is the source of
            % truth, rather than hard-coded widget defaults that silently
            % override it on the first pushConfigToRunner.
            c = obj.Runner.config;
            lab(g, 1, 4, 'ISI (s)');
            obj.IsiField = numField(g, 1, 5, ...
                sem.util.configField(c, 'isiS', 2.0), [0 Inf]);
            lab(g, 1, 6, 'dur (s)');
            obj.DurField = numField(g, 1, 7, ...
                sem.util.configField(c, 'durationS', 1.0), [1e-3 Inf]);

            obj.ModeDrop = uidropdown(g, 'Items', {'Voltage Clamp', 'Current Clamp'}, ...
                'ValueChangedFcn', @(~, ~) obj.onModeChanged());
            obj.ModeDrop.Layout.Row = 1; obj.ModeDrop.Layout.Column = 8;

            obj.TestPulseCheck = uicheckbox(g, 'Text', 'TestPulse', ...
                'Value', logical(sem.util.configField(c, 'testPulse', true)), ...
                'ValueChangedFcn', @(~, ~) obj.pushAndPreview());
            obj.TestPulseCheck.Layout.Row = 1; obj.TestPulseCheck.Layout.Column = 9;

            obj.SealBtn = uibutton(g, 'state', 'Text', 'Seal test', ...
                'ValueChangedFcn', @(s, ~) obj.onSealMode(s.Value));
            obj.SealBtn.Layout.Row = 1; obj.SealBtn.Layout.Column = 10;

            obj.FiBtn = uibutton(g, 'state', 'Text', 'F/I family', ...
                'ValueChangedFcn', @(~, ~) obj.pushConfigToRunner());
            obj.FiBtn.Layout.Row = 1; obj.FiBtn.Layout.Column = 11;

            b = uibutton(g, 'Text', 'Single', ...
                'ButtonPushedFcn', @(~, ~) obj.onSingle());
            b.Layout.Row = 1; b.Layout.Column = 12;

            b = uibutton(g, 'Text', 'Mapping…', 'BackgroundColor', [0.55 0.80 0.85], ...
                'ButtonPushedFcn', @(~, ~) obj.onMapping());
            b.Layout.Row = 1; b.Layout.Column = 13;

            % --- second row: identity + counters
            lab(g, 2, 1, 'Save path');
            obj.SavePathField = uieditfield(g, 'text', 'Value', obj.SessionDir);
            obj.SavePathField.Layout.Row = 2; obj.SavePathField.Layout.Column = [2 5];

            lab(g, 2, 6, 'Exp. name');
            obj.ExpNameField = uieditfield(g, 'text', 'Value', defaultExpName());
            obj.ExpNameField.Layout.Row = 2; obj.ExpNameField.Layout.Column = [7 8];

            obj.SaveEachCheck = uicheckbox(g, 'Text', 'save each sweep', 'Value', true);
            obj.SaveEachCheck.Layout.Row = 2; obj.SaveEachCheck.Layout.Column = 9;

            obj.SweepLabel = uilabel(g, 'Text', 'sweep 0', 'FontWeight', 'bold');
            obj.SweepLabel.Layout.Row = 2; obj.SweepLabel.Layout.Column = 10;

            obj.TimeLabel = uilabel(g, 'Text', '00:00');
            obj.TimeLabel.Layout.Row = 2; obj.TimeLabel.Layout.Column = 11;

            obj.StatusLabel = uilabel(g, 'Text', '');
            obj.StatusLabel.Layout.Row = 2; obj.StatusLabel.Layout.Column = [12 14];
        end

        function buildWatchColumn(obj, body)
            col = uigridlayout(body, [6 1]);
            col.Layout.Column = 1;
            col.RowHeight = {'1.7x', '0.8x', '0.7x', '0.7x', 30, '1.3x'};
            col.ColumnWidth = {'1x'};
            col.Padding = [0 0 0 0];
            col.RowSpacing = 4;

            [obj.LivePanel, obj.LiveAxes] = axesPanel(col, 1, 'Whole Cell 1');
            xlabel(obj.LiveAxes, 'seconds');

            [obj.RsPanel, obj.RsAxes] = axesPanel(col, 2, 'Rs (MOhm)');
            [obj.IhPanel, obj.IhAxes] = axesPanel(col, 3, 'Holding');
            [obj.IrPanel, obj.IrAxes] = axesPanel(col, 4, 'Rin (MOhm)');
            xlabel(obj.IrAxes, 'experiment time (min)');

            ctl = uigridlayout(col, [1 6]);
            ctl.Layout.Row = 5;
            ctl.ColumnWidth = {60, 60, 60, 60, 120, 110};
            ctl.Padding = [0 0 0 0];
            uilabel(ctl, 'Text', 'Sweep:');
            obj.BrowseField = uieditfield(ctl, 'numeric', 'Value', 0, ...
                'RoundFractionalValues', 'on', ...
                'ValueChangedFcn', @(s, ~) obj.showSweep(s.Value));
            uibutton(ctl, 'Text', '<--', 'ButtonPushedFcn', @(~, ~) obj.stepBrowse(-1));
            uibutton(ctl, 'Text', '-->', 'ButtonPushedFcn', @(~, ~) obj.stepBrowse(+1));
            obj.HoldLimitsCheck = uicheckbox(ctl, 'Text', 'Hold axes limits');
            obj.HoldPlotCheck = uicheckbox(ctl, 'Text', 'Hold plot');

            [obj.BrowsePanel, obj.BrowseAxes] = axesPanel(col, 6, 'Sweep browser');
            xlabel(obj.BrowseAxes, 'seconds');
        end

        function buildStimColumn(obj, body)
            col = uigridlayout(body, [2 1]);
            col.Layout.Column = 2;
            col.RowHeight = {'1x', '1x'};
            col.ColumnWidth = {'1x'};
            col.Padding = [0 0 0 0];
            col.RowSpacing = 6;

            ledDefaults = struct('amplitude', 0.4, 'pulseDurationMs', 500, ...
                'nPulses', 3, 'frequencyHz', 10, 'startTimeMs', 1, ...
                'amplitudeDeltaPerSweep', 0);
            obj.LedPanel = sem.gui.StimPanel(col, ...
                'Title', 'LED / laser control (AO)', ...
                'Channel', 'led', 'AmplitudeUnit', 'V', ...
                'DeltaLabel', 'delta per sweep', 'UpdateLabel', 'Update Pulses', ...
                'Defaults', ledDefaults);

            % Opens in voltage clamp, so the command starts at 0: a 200 mV step
            % into a clamped cell is meaningless and swamps the trace. The
            % clamp-mode switch sets a sensible amplitude for each mode, which
            % is what the legacy Cell1_type_popup did.
            cmdDefaults = struct('amplitude', 0, 'pulseDurationMs', 300, ...
                'nPulses', 1, 'frequencyHz', 1, 'startTimeMs', 300, ...
                'amplitudeDeltaPerSweep', 0);
            obj.CommandPanel = sem.gui.StimPanel(col, ...
                'Title', 'Cell 1 command / current injection (AO)', ...
                'Channel', 'command', 'AmplitudeUnit', 'mV', ...
                'DeltaLabel', 'delta current pulse', 'UpdateLabel', 'Update Cell1', ...
                'Defaults', cmdDefaults);
        end

        function buildMetaColumn(obj, body)
            p = uipanel(body, 'Title', 'Experiment', 'FontWeight', 'bold');
            p.Layout.Column = 3;
            names = {'animalId', 'ID#'; 'genotype', 'genotype'; 'age', 'age'; ...
                'virus', 'virus'; 'internal', 'internal'; ...
                'brainRegion', 'brain region'; 'lightSource', 'light source'; ...
                'cellDepth', 'cell depth'};
            g = uigridlayout(p, [size(names, 1) + 1, 1]);
            g.RowHeight = [repmat({46}, 1, size(names, 1)), {'1x'}];
            g.ColumnWidth = {'1x'};
            g.Padding = [4 4 4 4];
            g.RowSpacing = 2;
            for k = 1:size(names, 1)
                cell_ = uigridlayout(g, [2 1]);
                cell_.Layout.Row = k;
                cell_.RowHeight = {16, 24};
                cell_.Padding = [0 0 0 0];
                cell_.RowSpacing = 0;
                uilabel(cell_, 'Text', names{k, 2}, 'FontSize', 10);
                obj.MetaFields.(names{k, 1}) = uieditfield(cell_, 'text');
            end
        end

        function wire(obj)
            L = event.listener.empty(1, 0);
            L(end+1) = event.listener(obj.Runner, 'SweepFinished', @(~, ~) obj.onSweep());
            L(end+1) = event.listener(obj.Runner, 'StateChanged', @(~, ~) obj.onState());
            L(end+1) = event.listener(obj.Runner, 'AcquisitionError', @(~, ~) obj.onError());
            L(end+1) = event.listener(obj.LedPanel, 'Updated', @(~, ~) obj.pushAndPreview());
            L(end+1) = event.listener(obj.CommandPanel, 'Updated', @(~, ~) obj.pushAndPreview());
            obj.Listeners = L;
        end
    end

    % ------------------------------------------------------------- controls
    methods (Access = private)

        function pushConfigToRunner(obj)
            %pushConfigToRunner Copy the widgets into the runner's live config.
            %   Called on every edit; the runner re-reads at the top of each
            %   sweep, so this lands on the next sweep and never the one in
            %   flight.
            c = obj.Runner.config;
            c.durationS   = obj.DurField.Value;
            c.isiS        = obj.IsiField.Value;
            c.testPulse   = obj.TestPulseCheck.Value;
            c.sealTestMode = obj.SealBtn.Value;
            c.command     = obj.CommandPanel.spec();
            c.led         = obj.LedPanel.spec();
            obj.Runner.config = c;

            % F/I family: the command panel's delta drives the step. An
            % explicit step request on either panel wins over it.
            step = obj.CommandPanel.stepSpec();
            if isempty(step)
                step = obj.LedPanel.stepSpec();
            end
            if isempty(step) && obj.FiBtn.Value
                step = struct('channel', 'command', 'parameter', 'amplitude', ...
                    'delta', sem.util.configField( ...
                        sem.util.configField(obj.Config, 'sweep', struct()), 'fiStepPa', 20));
            end
            obj.Runner.stepSpec = step;
        end

        function pushAndPreview(obj)
            obj.pushConfigToRunner();
            obj.refreshPreviews();
        end

        function refreshPreviews(obj)
            try
                [cmd, led] = obj.Runner.previewSweep();
            catch ME
                obj.setStatus(ME.message);
                return
            end
            fs = sem.util.configField(obj.Runner.config, 'sampleRateHz', 20000);
            t = (0:numel(cmd) - 1)' / fs;
            obj.CommandPanel.drawPreview(t, cmd);
            obj.LedPanel.drawPreview(t, led);
        end

        function onStart(obj)
            obj.pushConfigToRunner();
            obj.Runner.start();
        end

        function onStop(obj)
            obj.Runner.stop();
            obj.PauseBtn.Value = false;
        end

        function onSingle(obj)
            obj.pushConfigToRunner();
            try
                obj.Runner.acquireOne();
            catch ME
                obj.setStatus(ME.message);
            end
        end

        function onPause(obj, isDown)
            if isDown
                obj.Runner.pause();
            else
                obj.Runner.resume();
            end
        end

        function onSealMode(obj, ~)
            obj.pushAndPreview();
        end

        function onModeChanged(obj)
            mode = 'VC';
            if startsWith(obj.ModeDrop.Value, 'Current')
                mode = 'IC';
            end
            obj.Telegraph.setMode(mode);
            % Switching mode changes what the amplitude number MEANS, so carry
            % a sensible default across rather than reinterpreting the old
            % number in the new units (a 200 mV clamp step, or a 0 pA
            % injection). The legacy Cell1_type_popup did the same.
            s = obj.CommandPanel.spec();
            if strcmp(mode, 'VC')
                obj.CommandPanel.setAmplitudeUnit('mV');
                ylabel(obj.LiveAxes, 'Im (pA)');
                obj.IhPanel.Title = 'Holding (pA)';
                s.amplitude = 0;
            else
                obj.CommandPanel.setAmplitudeUnit('pA');
                ylabel(obj.LiveAxes, 'Vm (mV)');
                obj.IhPanel.Title = 'Vrest (mV)';
                s.amplitude = 200;
            end
            obj.CommandPanel.setSpec(s);
            obj.pushAndPreview();
        end

        function onMapping(obj)
            % One NI board: the finite sweep path and the continuous block
            % session cannot both be live.
            obj.Runner.stop();
            obj.PauseBtn.Value = false;
            if isempty(obj.MappingWindow) || ~isvalid(obj.MappingWindow)
                obj.MappingWindow = sem.gui.MappingWindow(obj.Config, ...
                    'Rig', {obj.Dmd, obj.Daq}, 'SessionDir', obj.SessionDir, ...
                    'Targets', obj.Targets);
            else
                figure(obj.MappingWindow.Figure);
            end
        end
    end

    % ------------------------------------------------------------- updating
    methods (Access = private)

        function onSweep(obj)
            s = obj.Runner.lastSweep;
            if isempty(s)
                return
            end
            % The browser is a review tool, independent of acquisition: it
            % moves only when the operator navigates, so a sweep being examined
            % is not yanked away by the next one arriving. The live trace above
            % is what tracks acquisition.
            obj.Sweeps{end+1} = s;

            fs = s.sampleRateHz;
            t = (0:numel(s.ai) - 1)' / fs;
            dec = max(1, round(sem.util.configField( ...
                sem.util.configField(obj.Config, 'ui', struct()), 'livePlotDecimation', 1)));
            obj.LiveLine = drawInto(obj.LiveAxes, obj.LiveLine, ...
                t(1:dec:end), s.ai(1:dec:end), obj.HoldLimitsCheck.Value);

            n = obj.Runner.sweepCount;
            obj.LivePanel.Title = sprintf('Whole Cell 1 — sweep %d (%s)', n, s.mode);
            obj.SweepLabel.Text = sprintf('sweep %d', n);
            obj.TimeLabel.Text = mmss(s.timeMin);

            x = obj.Runner.sweepTimeMin;
            obj.RsLine = drawInto(obj.RsAxes, obj.RsLine, x, obj.Runner.rsMohm, false, 'o');
            obj.IhLine = drawInto(obj.IhAxes, obj.IhLine, x, obj.Runner.holding, false, 'o');
            obj.IrLine = drawInto(obj.IrAxes, obj.IrLine, x, obj.Runner.riMohm, false, 'o');

            obj.RsPanel.Title = numTitle('Rs', s.seal.rsMohm, 'MOhm');
            obj.IrPanel.Title = numTitle('Rin', s.seal.riMohm, 'MOhm');
            obj.IhPanel.Title = numTitle(holdingName(s.mode), s.seal.holding, s.seal.holdingUnit);

            % A stepped family rewrites the panel so it shows what is being
            % delivered, not what was first typed.
            if ~isempty(obj.Runner.stepSpec)
                ch = obj.Runner.stepSpec.channel;
                if strcmp(ch, 'command')
                    obj.CommandPanel.setSpec(obj.Runner.config.command);
                else
                    obj.LedPanel.setSpec(obj.Runner.config.led);
                end
                obj.refreshPreviews();
            end
            drawnow limitrate;
        end

        function onState(obj)
            st = obj.Runner.state;
            obj.setStatus(st);
            running = strcmp(st, 'Running');
            obj.StopBtn.Enable = onOff(~strcmp(st, 'Idle'));
            obj.PauseBtn.Enable = onOff(~strcmp(st, 'Idle'));
            obj.StartBtn.Enable = onOff(~running);
        end

        function onError(obj)
            e = obj.Runner.lastError;
            if ~isempty(e)
                obj.setStatus(sprintf('ERROR: %s', e.message));
            end
        end

        function onSaveSweep(obj, s)
            if ~obj.SaveEachCheck.Value
                return
            end
            try
                sem.io.saveSweep(s, obj.sweepDir(), obj.Config, obj.metadata());
            catch ME
                obj.setStatus(sprintf('save failed: %s', ME.message));
            end
        end

        function m = metadata(obj)
            m = struct();
            f = fieldnames(obj.MetaFields);
            for k = 1:numel(f)
                m.(f{k}) = char(obj.MetaFields.(f{k}).Value);
            end
        end

        function stepBrowse(obj, d)
            obj.showSweep(obj.BrowseIdx + d);
        end

        function showSweep(obj, idx)
            idx = round(idx);
            if isempty(obj.Sweeps) || idx < 1 || idx > numel(obj.Sweeps)
                obj.BrowseField.Value = obj.BrowseIdx;
                return   % silently ignore, as the legacy browser did
            end
            obj.BrowseIdx = idx;
            obj.BrowseField.Value = idx;
            s = obj.Sweeps{idx};
            t = (0:numel(s.ai) - 1)' / s.sampleRateHz;
            if obj.HoldPlotCheck.Value
                hold(obj.BrowseAxes, 'on');
                plot(obj.BrowseAxes, t, s.ai);
            else
                hold(obj.BrowseAxes, 'off');
                obj.BrowseLineReset(t, s.ai);
                ylim(obj.BrowseAxes, sem.gui.paddedLimits(s.ai));
                xlim(obj.BrowseAxes, [t(1), t(end)]);
            end
            obj.BrowsePanel.Title = sprintf('Sweep browser — sweep %d (%s)', idx, s.mode);
        end

        function BrowseLineReset(obj, t, y)
            cla(obj.BrowseAxes);
            plot(obj.BrowseAxes, t, y);
        end

        function setStatus(obj, txt)
            if ~isempty(obj.StatusLabel) && isvalid(obj.StatusLabel)
                obj.StatusLabel.Text = char(txt);
            end
        end

        function attachSimulatedCells(obj)
            targets = sem.targeting.mockTargets(obj.Config);
            if isnan(targets.patchedCellId)
                xy = reshape([targets.cells.dmdXY], 2, []).';
                [~, k] = min(vecnorm(xy - mean(xy, 1), 2, 2));
                targets.patchedCellId = targets.cells(k).id;
            end
            obj.Targets = targets;
            obj.Model = sem.sim.makeGroundTruthNetwork(obj.Config, targets);
            obj.Daq.attachNetworkModel(obj.Model);
        end
    end

    methods (Static, Access = private)
        function root = repoRoot()
            root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
        end

        function config = resolveConfig(configOrPath)
            if isstruct(configOrPath)
                config = configOrPath;
            else
                config = tfp.io.loadConfig(char(configOrPath));
            end
        end

        function s = sweepConfigFrom(config)
            %sweepConfigFrom Seed the sweep config from the rig YAML.
            eCfg = sem.util.configField(config, 'ephys', struct());
            dCfg = sem.util.configField(config, 'daq', struct());
            sCfg = sem.util.configField(config, 'sweep', struct());
            s = eCfg;                       % carries the flat sealTest_* keys
            s.sampleRateHz = sem.util.configField(dCfg, 'sampleRate', 20000);
            s.durationS  = sem.util.configField(sCfg, 'durationS', 1.0);
            s.isiS       = sem.util.configField(sCfg, 'isiS', 2.0);
            s.testPulse  = logical(sem.util.configField(sCfg, 'testPulse', true));
            s.testPulseStartMs = sem.util.configField(sCfg, 'testPulseStartMs', 50);
            s.sealTestIsiS = sem.util.configField(sCfg, 'sealTestIsiS', 0.5);
            s.sealTestDurationS = sem.util.configField(sCfg, 'sealTestDurationS', 0.2);
            s.command = struct();
            s.led = struct();
        end
    end
end

% --- local helpers ---------------------------------------------------------

function [p, ax] = axesPanel(parent, row, titleText)
%axesPanel Axes filling a titled panel.
%   The axes goes inside a 1x1 uigridlayout rather than straight into the
%   panel: a nested uipanel positioned [0 0 1 1] does NOT take its parent's
%   size (it keeps the default ~260 px), which left every plot a fraction of
%   its allocated width. A grid sizes its child to the panel and reserves room
%   for the tick labels, so the plot no longer rides up into the panel title
%   either. The title doubles as the numeric readout for the trend strips.
p = uipanel(parent, 'Title', titleText, 'FontWeight', 'bold');
p.Layout.Row = row;
g = uigridlayout(p, [1 1]);
g.Padding = [2 2 2 2];
g.RowHeight = {'1x'};
g.ColumnWidth = {'1x'};
ax = uiaxes(g);
ax.FontSize = 8;
end

function h = drawInto(ax, h, x, y, holdLimits, marker)
if nargin < 6
    marker = '-';
end
xl = xlim(ax); yl = ylim(ax);
if isempty(h) || ~isvalid(h)
    h = plot(ax, x, y, marker);
else
    set(h, 'XData', x, 'YData', y);
end
if holdLimits
    xlim(ax, xl); ylim(ax, yl);
else
    % Never let the baseline sit on the axis edge, where it reads as missing.
    ylim(ax, sem.gui.paddedLimits(y));
    if strcmp(marker, '-')
        % Continuous trace: the sweep spans exactly its own duration.
        if numel(x) > 1 && x(end) > x(1)
            xlim(ax, [x(1), x(end)]);
        end
    else
        % Trend markers: pad x too, or the first and last points are drawn
        % half outside the plot box.
        xlim(ax, sem.gui.paddedLimits(x, 0.05));
    end
end
end

function t = numTitle(name, value, unit)
if isnan(value)
    t = sprintf('%s — n/a', name);
else
    t = sprintf('%s = %.1f %s', name, value, char(unit));
end
end

function n = holdingName(mode)
if strcmp(mode, 'IC')
    n = 'Vrest';
else
    n = 'Holding';
end
end

function s = mmss(minutes)
totalSec = round(minutes * 60);
s = sprintf('%02d:%02d', floor(totalSec / 60), mod(totalSec, 60));
end

function v = onOff(tf)
if tf, v = 'on'; else, v = 'off'; end
end

function lab(g, r, c, txt)
h = uilabel(g, 'Text', txt);
h.Layout.Row = r; h.Layout.Column = c;
end

function f = numField(g, r, c, value, limits)
f = uieditfield(g, 'numeric', 'Value', value, 'Limits', limits);
f.Layout.Row = r; f.Layout.Column = c;
end

function n = defaultExpName()
n = [datestr(now, 'mmddyy') 'a']; %#ok<TNOW1,DATST>
end
