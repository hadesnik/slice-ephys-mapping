classdef Round3_CommandEditorPanelTest < matlab.unittest.TestCase
    % Round3_CommandEditorPanelTest  Headless tests for the command stim editor,
    % including the mode-driven amplitude label.

    properties
        Fig
        Panel
        EventCount double = 0
    end

    methods (TestMethodSetup)
        function makeFigure(tc)
            tc.Fig = uifigure('Visible', 'off');
            tc.Panel = patchclamp.gui.CommandEditorPanel(tc.Fig);
            tc.EventCount = 0;
            addlistener(tc.Panel, 'ConfigChanged', @(~,~) tc.bumpEvent());
        end
    end

    methods (TestMethodTeardown)
        function closeFigure(tc)
            if isvalid(tc.Fig)
                close(tc.Fig);
            end
        end
    end

    methods
        function bumpEvent(tc)
            tc.EventCount = tc.EventCount + 1;
        end
    end

    methods (Test)
        function testInitialModeIsVc(tc)
            tc.verifyEqual(tc.Panel.Mode, "VC");
            ampLabel = findall(tc.Panel.Panel, 'Tag', 'amplitudeLabel');
            tc.verifyTrue(contains(ampLabel.Text, "mV"));
            tc.verifyFalse(contains(ampLabel.Text, "pA"));
        end

        function testSetModeIcFlipsLabel(tc)
            tc.Panel.setMode("IC");
            ampLabel = findall(tc.Panel.Panel, 'Tag', 'amplitudeLabel');
            tc.verifyTrue(contains(ampLabel.Text, "pA"));

            ax = findall(tc.Panel.Panel, 'Tag', 'previewAxes');
            tc.verifyTrue(contains(ax.YLabel.String, "pA"));
        end

        function testSetModeVcRestoresLabel(tc)
            tc.Panel.setMode("IC");
            tc.Panel.setMode("VC");
            ampLabel = findall(tc.Panel.Panel, 'Tag', 'amplitudeLabel');
            tc.verifyTrue(contains(ampLabel.Text, "mV"));

            ax = findall(tc.Panel.Panel, 'Tag', 'previewAxes');
            tc.verifyTrue(contains(ax.YLabel.String, "mV"));
        end

        function testSetModePreservesAmplitudeValue(tc)
            tc.setField('amplitudeField', -65);
            tc.Panel.setMode("IC");
            ampField = findall(tc.Panel.Panel, 'Tag', 'amplitudeField');
            tc.verifyEqual(ampField.Value, -65);
            tc.Panel.setMode("VC");
            tc.verifyEqual(ampField.Value, -65);
        end

        function testUpdateValidParamsFiresConfigChanged(tc)
            tc.setField('pulseDurationField', 4);
            tc.setField('amplitudeField', -70);
            tc.setField('frequencyField', 5);
            tc.setField('nPulsesField', 3);
            tc.pressButton('updateButton');

            tc.verifyEqual(tc.EventCount, 1);
            tc.verifyEqual(tc.Panel.Config.amplitude, -70);
            tc.verifyEqual(tc.Panel.Config.nPulses, 3);
        end

        function testUpdateInvalidParamsKeepsConfig(tc)
            before = tc.Panel.Config;
            tc.setField('nPulsesField', -3);  % invalid
            tc.pressButton('updateButton');

            tc.verifyEqual(tc.Panel.Config, before);
            tc.verifyEqual(tc.EventCount, 0);
            status = findall(tc.Panel.Panel, 'Tag', 'statusLabel');
            tc.verifyNotEmpty(status.Text);
        end

        function testClear(tc)
            tc.pressButton('clearButton');
            tc.verifyEqual(tc.Panel.Config.nPulses, 0);
            tc.verifyEqual(tc.Panel.Config.amplitude, 0);
            tc.verifyEqual(tc.EventCount, 1);
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
