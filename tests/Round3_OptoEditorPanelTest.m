classdef Round3_OptoEditorPanelTest < matlab.unittest.TestCase
    % Round3_OptoEditorPanelTest  Headless tests for the optogenetic stim editor.

    properties
        Fig
        Panel
        EventCount double = 0
    end

    methods (TestMethodSetup)
        function makeFigure(tc)
            tc.Fig = uifigure('Visible', 'off');
            tc.Panel = patchclamp.gui.OptoEditorPanel(tc.Fig);
            tc.EventCount = 0;
            addlistener(tc.Panel, 'ConfigChanged', @(~,~) tc.bumpEvent());
        end
    end

    methods
        function bumpEvent(tc)
            tc.EventCount = tc.EventCount + 1;
        end
    end

    methods (TestMethodTeardown)
        function closeFigure(tc)
            if isvalid(tc.Fig)
                close(tc.Fig);
            end
        end
    end

    methods (Test)
        function testConstructionPopulatesDefaultConfig(tc)
            expected = patchclamp.config.PulseTrainConfig.defaultConfig();
            tc.verifyEqual(tc.Panel.Config, expected);

            ampLabel = findall(tc.Panel.Panel, 'Tag', 'amplitudeLabel');
            tc.verifyNotEmpty(ampLabel);
            tc.verifyTrue(contains(ampLabel.Text, "% brightness"));
        end

        function testUpdateValidParamsFiresConfigChanged(tc)
            tc.setField('pulseDurationField', 3);
            tc.setField('amplitudeField', 75);
            tc.setField('frequencyField', 10);
            tc.setField('nPulsesField', 5);

            tc.pressButton('updateButton');

            tc.verifyEqual(tc.EventCount, 1);
            tc.verifyEqual(tc.Panel.Config.pulseDurationMs, 3);
            tc.verifyEqual(tc.Panel.Config.amplitude, 75);
            tc.verifyEqual(tc.Panel.Config.frequencyHz, 10);
            tc.verifyEqual(tc.Panel.Config.nPulses, 5);
        end

        function testUpdateInvalidParamsDoesNotChangeConfig(tc)
            before = tc.Panel.Config;
            tc.setField('frequencyField', -5);  % invalid: must be positive
            tc.pressButton('updateButton');

            tc.verifyEqual(tc.Panel.Config, before);
            tc.verifyEqual(tc.EventCount, 0);

            status = findall(tc.Panel.Panel, 'Tag', 'statusLabel');
            tc.verifyNotEmpty(status.Text);
        end

        function testClearZeroesConfigAndFiresEvent(tc)
            tc.pressButton('clearButton');

            tc.verifyEqual(tc.Panel.Config.nPulses, 0);
            tc.verifyEqual(tc.Panel.Config.amplitude, 0);
            tc.verifyEqual(tc.EventCount, 1);
        end

        function testPreviewIsRenderedAfterUpdate(tc)
            tc.setField('pulseDurationField', 5);
            tc.setField('amplitudeField', 50);
            tc.setField('frequencyField', 20);
            tc.setField('nPulsesField', 4);
            tc.pressButton('updateButton');

            ax = findall(tc.Panel.Panel, 'Tag', 'previewAxes');
            tc.verifyNotEmpty(ax);
            lines = findobj(ax, 'Type', 'line');
            tc.verifyGreaterThanOrEqual(numel(lines), 1);
        end

        function testValidateFitsWindowRespected(tc)
            before = tc.Panel.Config;
            tc.setField('frequencyField', 1);
            tc.setField('nPulsesField', 100);   % 100 pulses at 1 Hz -> 100 s, way more than 0.7 s
            tc.pressButton('updateButton');

            tc.verifyEqual(tc.Panel.Config, before);
            status = findall(tc.Panel.Panel, 'Tag', 'statusLabel');
            tc.verifyTrue(contains(status.Text, "stimulus window") || contains(status.Text, "Pulse train"));
        end

        function testSetStimulusWindowSecAffectsValidation(tc)
            % 5 pulses at 10 Hz -> 0.5 s. Fits in default 0.7 s, but not in 0.3 s.
            tc.setField('pulseDurationField', 2);
            tc.setField('amplitudeField', 50);
            tc.setField('frequencyField', 10);
            tc.setField('nPulsesField', 5);
            tc.pressButton('updateButton');
            tc.verifyEqual(tc.Panel.Config.nPulses, 5);

            tc.Panel.setStimulusWindowSec(0.3);
            before = tc.Panel.Config;
            % Push the same params back through Update: should now fail.
            tc.pressButton('updateButton');
            tc.verifyEqual(tc.Panel.Config, before);
            status = findall(tc.Panel.Panel, 'Tag', 'statusLabel');
            tc.verifyNotEmpty(status.Text);
        end
    end

    methods (Access = private)
        function setField(tc, tagName, value)
            h = findall(tc.Panel.Panel, 'Tag', tagName);
            tc.assertNotEmpty(h);
            h.Value = value;
            if ~isempty(h.ValueChangedFcn)
                h.ValueChangedFcn(h, struct('Value', value, 'PreviousValue', value));
            end
        end

        function pressButton(tc, tagName)
            h = findall(tc.Panel.Panel, 'Tag', tagName);
            tc.assertNotEmpty(h);
            if ~isempty(h.ButtonPushedFcn)
                h.ButtonPushedFcn(h, struct('Source', h));
            end
        end
    end
end
