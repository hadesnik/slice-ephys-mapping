classdef Round3_Editors < matlab.unittest.TestCase
    % Round3_Editors  Round 3a Agent H acceptance tests for the two stim-editor
    % panels (OptoEditorPanel + CommandEditorPanel).
    %
    % Covers the spec contract:
    %   - Update with valid params fires CommandUpdated / OptoUpdated.
    %   - Update with invalid params does NOT fire the event and surfaces the
    %     validation error in the panel's status label (uialert is also issued
    %     against the parent uifigure; it is non-blocking so headless tests
    %     never hang).
    %   - currentConfig() returns the last validated PulseTrainConfig struct.
    %   - CommandEditorPanel.setMode flips the amplitude label between mV and pA.
    %
    % All tests run headless on macOS in an invisible uifigure.

    properties
        Fig
        CommandUpdatedCount double = 0
        OptoUpdatedCount    double = 0
    end

    methods (TestMethodSetup)
        function makeFigure(tc)
            tc.Fig = uifigure('Visible', 'off');
            tc.CommandUpdatedCount = 0;
            tc.OptoUpdatedCount    = 0;
        end
    end

    methods (TestMethodTeardown)
        function closeFigure(tc)
            if ~isempty(tc.Fig) && isvalid(tc.Fig)
                close(tc.Fig);
            end
        end
    end

    methods
        function bumpCommand(tc, ~, ~)
            tc.CommandUpdatedCount = tc.CommandUpdatedCount + 1;
        end
        function bumpOpto(tc, ~, ~)
            tc.OptoUpdatedCount = tc.OptoUpdatedCount + 1;
        end
    end

    methods (Test)
        % --- CommandEditorPanel --------------------------------------------------

        function testCommandUpdateValidFiresEventAndExposesConfig(tc)
            panel = patchclamp.gui.CommandEditorPanel(tc.Fig);
            addlistener(panel, 'CommandUpdated', @(s,e) tc.bumpCommand(s,e));

            tc.setField(panel, 'pulseDurationField', 4);
            tc.setField(panel, 'amplitudeField',     -70);
            tc.setField(panel, 'frequencyField',     5);
            tc.setField(panel, 'nPulsesField',       3);
            tc.pressButton(panel, 'updateButton');

            tc.verifyEqual(tc.CommandUpdatedCount, 1);
            cfg = panel.currentConfig();
            tc.verifyEqual(cfg.pulseDurationMs, 4);
            tc.verifyEqual(cfg.amplitude,       -70);
            tc.verifyEqual(cfg.frequencyHz,     5);
            tc.verifyEqual(cfg.nPulses,         3);

            % Round-trip through the canonical validator: must accept this.
            patchclamp.config.PulseTrainConfig.validate(cfg);
        end

        function testCommandUpdateInvalidSuppressesEvent(tc)
            panel = patchclamp.gui.CommandEditorPanel(tc.Fig);
            addlistener(panel, 'CommandUpdated', @(s,e) tc.bumpCommand(s,e));
            before = panel.currentConfig();

            % nPulses * (1/freq) = 1000 * 1 s = 1000 s, way more than 0.7 s window.
            tc.setField(panel, 'frequencyField', 1);
            tc.setField(panel, 'nPulsesField',   1000);
            tc.pressButton(panel, 'updateButton');

            tc.verifyEqual(tc.CommandUpdatedCount, 0);
            tc.verifyEqual(panel.currentConfig(), before);

            status = findall(panel.Panel, 'Tag', 'statusLabel');
            tc.verifyNotEmpty(status);
            tc.verifyNotEmpty(status.Text);
        end

        function testCommandSetModeFlipsAmplitudeLabel(tc)
            panel = patchclamp.gui.CommandEditorPanel(tc.Fig);
            ampLabel = findall(panel.Panel, 'Tag', 'amplitudeLabel');

            tc.verifyTrue(contains(ampLabel.Text, "mV"));
            tc.verifyFalse(contains(ampLabel.Text, "pA"));

            panel.setMode("IC");
            tc.verifyTrue(contains(ampLabel.Text, "pA"));
            tc.verifyFalse(contains(ampLabel.Text, "mV"));

            ax = findall(panel.Panel, 'Tag', 'previewAxes');
            tc.verifyTrue(contains(ax.YLabel.String, "pA"));

            panel.setMode("VC");
            tc.verifyTrue(contains(ampLabel.Text, "mV"));
            tc.verifyTrue(contains(ax.YLabel.String, "mV"));
        end

        function testCommandPreviewMatchesRunnerWaveform(tc)
            % The preview must be rendered by the actual protocol.PulseTrain
            % builder; verify by re-running the builder with the same config
            % and the same sample rate / window the panel uses, then checking
            % the rendered line peak amplitude matches.
            panel = patchclamp.gui.CommandEditorPanel(tc.Fig);
            tc.setField(panel, 'pulseDurationField', 5);
            tc.setField(panel, 'amplitudeField',     -50);
            tc.setField(panel, 'frequencyField',     20);
            tc.setField(panel, 'nPulsesField',       4);
            tc.pressButton(panel, 'updateButton');

            ax = findall(panel.Panel, 'Tag', 'previewAxes');
            lines = findobj(ax, 'Type', 'line');
            tc.assertGreaterThanOrEqual(numel(lines), 1);
            yData = lines(1).YData;
            tc.verifyEqual(min(yData), -50, "AbsTol", 1e-9);

            % And independently rebuild via the same code path the runner uses.
            cfg = panel.currentConfig();
            wf = patchclamp.protocol.PulseTrain.build(cfg, 20000, 0.7, "mV");
            tc.verifyEqual(min(wf), -50, "AbsTol", 1e-9);
        end

        % --- OptoEditorPanel -----------------------------------------------------

        function testOptoUpdateValidFiresEventAndExposesConfig(tc)
            panel = patchclamp.gui.OptoEditorPanel(tc.Fig);
            addlistener(panel, 'OptoUpdated', @(s,e) tc.bumpOpto(s,e));

            tc.setField(panel, 'pulseDurationField', 3);
            tc.setField(panel, 'amplitudeField',     75);
            tc.setField(panel, 'frequencyField',     10);
            tc.setField(panel, 'nPulsesField',       5);
            tc.pressButton(panel, 'updateButton');

            tc.verifyEqual(tc.OptoUpdatedCount, 1);
            cfg = panel.currentConfig();
            tc.verifyEqual(cfg.pulseDurationMs, 3);
            tc.verifyEqual(cfg.amplitude,       75);
            tc.verifyEqual(cfg.frequencyHz,     10);
            tc.verifyEqual(cfg.nPulses,         5);

            patchclamp.config.PulseTrainConfig.validate(cfg);
        end

        function testOptoUpdateWindowOverrunSuppressesEvent(tc)
            panel = patchclamp.gui.OptoEditorPanel(tc.Fig);
            addlistener(panel, 'OptoUpdated', @(s,e) tc.bumpOpto(s,e));
            before = panel.currentConfig();

            tc.setField(panel, 'frequencyField', 1);
            tc.setField(panel, 'nPulsesField',   100);  % 100 s required, 0.7 s window
            tc.pressButton(panel, 'updateButton');

            tc.verifyEqual(tc.OptoUpdatedCount, 0);
            tc.verifyEqual(panel.currentConfig(), before);
            status = findall(panel.Panel, 'Tag', 'statusLabel');
            tc.verifyNotEmpty(status.Text);
        end

        function testOptoUpdateOutOfRangePercentSuppressesEvent(tc)
            panel = patchclamp.gui.OptoEditorPanel(tc.Fig);
            addlistener(panel, 'OptoUpdated', @(s,e) tc.bumpOpto(s,e));
            before = panel.currentConfig();

            % 150 % is outside the LED driver's 0..100 range.
            tc.setField(panel, 'amplitudeField', 150);
            tc.pressButton(panel, 'updateButton');

            tc.verifyEqual(tc.OptoUpdatedCount, 0);
            tc.verifyEqual(panel.currentConfig(), before);
        end

        function testOptoPreviewIsInPercentUnits(tc)
            panel = patchclamp.gui.OptoEditorPanel(tc.Fig);
            tc.setField(panel, 'pulseDurationField', 5);
            tc.setField(panel, 'amplitudeField',     80);
            tc.setField(panel, 'frequencyField',     10);
            tc.setField(panel, 'nPulsesField',       4);
            tc.pressButton(panel, 'updateButton');

            ax = findall(panel.Panel, 'Tag', 'previewAxes');
            lines = findobj(ax, 'Type', 'line');
            tc.assertGreaterThanOrEqual(numel(lines), 1);
            yData = lines(1).YData;

            % Peak of preview should be ~80 (in percent), not 4 V.
            tc.verifyEqual(max(yData), 80, "AbsTol", 1e-6);
            tc.verifyTrue(contains(ax.YLabel.String, "%"));
        end
    end

    methods (Access = private)
        function setField(~, panel, tagName, value)
            h = findall(panel.Panel, 'Tag', tagName);
            assert(~isempty(h), "field tag '%s' not found", tagName);
            h.Value = value;
            if ~isempty(h.ValueChangedFcn)
                h.ValueChangedFcn(h, struct('Value', value, 'PreviousValue', value));
            end
        end

        function pressButton(~, panel, tagName)
            h = findall(panel.Panel, 'Tag', tagName);
            assert(~isempty(h), "button tag '%s' not found", tagName);
            if ~isempty(h.ButtonPushedFcn)
                h.ButtonPushedFcn(h, struct('Source', h));
            end
        end
    end
end
