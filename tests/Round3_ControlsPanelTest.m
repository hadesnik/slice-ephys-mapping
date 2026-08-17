classdef Round3_ControlsPanelTest < matlab.unittest.TestCase
    % Round3_ControlsPanelTest  Tests for patchclamp.gui.ControlsPanel.
    %
    % Runs in -batch mode against an invisible uifigure. Each test gets a
    % fresh figure (TestMethodSetup/Teardown) so callbacks from one test
    % cannot leak into another. Buttons and edit-field callbacks are
    % invoked directly rather than through synthetic input events, which
    % is the standard pattern for headless uifigure testing.

    properties
        Fig
        Panel
    end

    methods (TestMethodSetup)
        function makeFigure(testCase)
            testCase.Fig = uifigure("Visible", "off");
        end
    end

    methods (TestMethodTeardown)
        function closeFigure(testCase)
            if ~isempty(testCase.Fig) && isvalid(testCase.Fig)
                close(testCase.Fig);
            end
            testCase.Fig = [];
            testCase.Panel = [];
        end
    end

    methods (Access = private)
        function p = makePanel(testCase, overrides)
            arguments
                testCase
                overrides (1,1) struct = struct()
            end
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            cfg.cellId = "cellA";
            fn = fieldnames(overrides);
            for k = 1:numel(fn)
                cfg.(fn{k}) = overrides.(fn{k});
            end
            p = patchclamp.gui.ControlsPanel(testCase.Fig, cfg);
            testCase.Panel = p;
        end

        function fireEdit(~, field, newValue)
            % Drive a uieditfield ValueChangedFcn the same way the GUI does.
            prev = field.Value;
            field.Value = newValue;
            ev = struct("Value", newValue, "PreviousValue", prev);
            field.ValueChangedFcn(field, ev);
        end
    end

    methods (Test)

        function testConstructionLaysOutAllControls(testCase)
            p = testCase.makePanel();
            testCase.verifyClass(p.Panel, "matlab.ui.container.Panel");

            startBtn = findall(p.Panel, "Type", "uibutton", "Text", "Start");
            stopBtn  = findall(p.Panel, "Type", "uibutton", "Text", "Stop");
            testCase.verifyNumElements(startBtn, 1);
            testCase.verifyNumElements(stopBtn, 1);

            numFields = findall(p.Panel, "Type", "uinumericeditfield");
            textFields = findall(p.Panel, "Type", "uieditfield");
            testCase.verifyGreaterThanOrEqual(numel(numFields), 2);
            testCase.verifyGreaterThanOrEqual(numel(textFields), 1);

            labels = findall(p.Panel, "Type", "uilabel");
            testCase.verifyGreaterThanOrEqual(numel(labels), 4);
        end

        function testInitialValuesPopulated(testCase)
            cfg = struct();
            cfg.itiSec         = 2.5;
            cfg.trialLengthSec = 0.75;
            cfg.cellId         = "neuronX";
            p = testCase.makePanel(cfg);

            testCase.verifyEqual(p.ItiSec, 2.5);
            testCase.verifyEqual(p.TrialLengthSec, 0.75);
            testCase.verifyEqual(p.CellId, "neuronX");
        end

        function testStartButtonFiresEvent(testCase)
            p = testCase.makePanel();
            count = 0;
            lh = addlistener(p, "StartRequested", @(~,~) increment());
            cleanup = onCleanup(@() delete(lh)); %#ok<NASGU>
            function increment(), count = count + 1; end

            btn = findall(p.Panel, "Type", "uibutton", "Text", "Start");
            btn.ButtonPushedFcn(btn, []);
            testCase.verifyEqual(count, 1);
        end

        function testStopButtonFiresEvent(testCase)
            p = testCase.makePanel();
            % Stop is initially disabled but its callback still runs when
            % invoked directly; the GUI gates the click, not the callback.
            % To stay realistic, enable Running first.
            p.setRunningState("Running");

            count = 0;
            lh = addlistener(p, "StopRequested", @(~,~) increment());
            cleanup = onCleanup(@() delete(lh)); %#ok<NASGU>
            function increment(), count = count + 1; end

            btn = findall(p.Panel, "Type", "uibutton", "Text", "Stop");
            btn.ButtonPushedFcn(btn, []);
            testCase.verifyEqual(count, 1);
        end

        function testItiEditFiresEvent(testCase)
            p = testCase.makePanel();
            fired = false;
            seen  = 0;
            lh = addlistener(p, "ItiChanged", @(src,~) onFire(src));
            cleanup = onCleanup(@() delete(lh)); %#ok<NASGU>
            function onFire(src), fired = true; seen = src.ItiSec; end

            testCase.fireEdit(p.ItiField, 3.25);
            testCase.verifyTrue(fired);
            testCase.verifyEqual(seen, 3.25);
            testCase.verifyEqual(p.ItiSec, 3.25);
        end

        function testTrialLengthEditFiresEvent(testCase)
            p = testCase.makePanel();
            fired = false;
            seen  = 0;
            lh = addlistener(p, "TrialLengthChanged", @(src,~) onFire(src));
            cleanup = onCleanup(@() delete(lh)); %#ok<NASGU>
            function onFire(src), fired = true; seen = src.TrialLengthSec; end

            testCase.fireEdit(p.TrialLengthField, 1.5);
            testCase.verifyTrue(fired);
            testCase.verifyEqual(seen, 1.5);
            testCase.verifyEqual(p.TrialLengthSec, 1.5);
        end

        function testCellIdFiresEvent(testCase)
            p = testCase.makePanel();
            fired = false;
            seen  = "";
            lh = addlistener(p, "CellIdChanged", @(src,~) onFire(src));
            cleanup = onCleanup(@() delete(lh)); %#ok<NASGU>
            function onFire(src), fired = true; seen = src.CellId; end

            testCase.fireEdit(p.CellIdField, 'cellZ');
            testCase.verifyTrue(fired);
            testCase.verifyEqual(seen, "cellZ");
            testCase.verifyEqual(p.CellId, "cellZ");
        end

        function testSetModeUpdatesLabel(testCase)
            p = testCase.makePanel();
            p.setMode("IC");
            testCase.verifySubstring(p.ModeLabel.Text, "IC");

            p.setMode("VC");
            testCase.verifySubstring(p.ModeLabel.Text, "VC");
        end

        function testSetRunningStateEnablesCorrectButtons(testCase)
            p = testCase.makePanel();

            p.setRunningState("Idle");
            testCase.verifyEqual(string(p.StartButton.Enable), "on");
            testCase.verifyEqual(string(p.StopButton.Enable),  "off");

            p.setRunningState("Running");
            testCase.verifyEqual(string(p.StartButton.Enable), "off");
            testCase.verifyEqual(string(p.StopButton.Enable),  "on");

            p.setRunningState("Stopping");
            testCase.verifyEqual(string(p.StartButton.Enable), "off");
            testCase.verifyEqual(string(p.StopButton.Enable),  "off");
        end

        function testSetTrialCountAppearsInStatus(testCase)
            p = testCase.makePanel();
            p.setRunningState("Running");
            p.setTrialCount(7);
            testCase.verifySubstring(p.StatusLabel.Text, "7");
            testCase.verifySubstring(p.StatusLabel.Text, "Running");
        end

        function testSetGainDisplay(testCase)
            p = testCase.makePanel();
            g = struct( ...
                'commandVcMvPerV', 20, ...
                'commandIcPaPerV', 400, ...
                'scaledVcPaPerV',  1000, ...
                'scaledIcMvPerMv', 20);
            p.setGainDisplay(g);

            txt = string(p.GainLabel.Text);
            testCase.verifySubstring(txt, "1000");
            testCase.verifySubstring(txt, "20");
            testCase.verifySubstring(txt, "400");
        end

        function testSetStatusTextOverrides(testCase)
            p = testCase.makePanel();
            p.setRunningState("Running");
            p.setTrialCount(3);
            p.setStatusText("Error: pipette lost");
            testCase.verifySubstring(p.StatusLabel.Text, "Error");

            % Re-rendering state clears the override.
            p.setRunningState("Idle");
            testCase.verifyEqual(any(strfind(p.StatusLabel.Text, "Error")), false);
        end
    end
end
