classdef Round3_TrialPlotPanelTest < matlab.unittest.TestCase
    % Round3_TrialPlotPanelTest  Tests for patchclamp.gui.TrialPlotPanel.
    %
    % Runs headlessly: uifigure is created with 'Visible','off'. Each test
    % creates its own figure in TestMethodSetup and closes it in teardown.

    properties
        Fig
        Panel
    end

    properties (Constant)
        Fs = 20000;   % Hz
    end

    methods (TestMethodSetup)
        function makeFigure(testCase)
            testCase.Fig = uifigure('Visible', 'off');
            testCase.Panel = patchclamp.gui.TrialPlotPanel(testCase.Fig);
        end
    end

    methods (TestMethodTeardown)
        function closeFigure(testCase)
            if ~isempty(testCase.Fig) && isvalid(testCase.Fig)
                close(testCase.Fig);
            end
        end
    end

    methods (Static, Access = private)
        function y = sineTrace(fs)
            n = round(0.5 * fs);
            t = (0:n-1)' / fs;
            y = sin(2*pi*10*t);
        end
    end

    methods (Test)

        function testAddOneTrialCreatesOneLine(testCase)
            y = Round3_TrialPlotPanelTest.sineTrace(testCase.Fs);
            testCase.Panel.addTrial(y, testCase.Fs, "VC");

            lines = findall(testCase.Panel.Panel, 'Type', 'line');
            testCase.verifyEqual(numel(lines), 1);
        end

        function testAddSixTrialsKeepsLastFive(testCase)
            y = Round3_TrialPlotPanelTest.sineTrace(testCase.Fs);
            for k = 1:6
                testCase.Panel.addTrial(y * k, testCase.Fs, "VC");
            end
            lines = findall(testCase.Panel.Panel, 'Type', 'line');
            testCase.verifyEqual(numel(lines), 5);
        end

        function testNewestLineIsFullOpacity(testCase)
            y = Round3_TrialPlotPanelTest.sineTrace(testCase.Fs);
            testCase.Panel.addTrial(y,     testCase.Fs, "VC");
            testCase.Panel.addTrial(y * 2, testCase.Fs, "VC");
            testCase.Panel.addTrial(y * 3, testCase.Fs, "VC");

            lines = findall(testCase.Panel.Panel, 'Type', 'line');
            % findall returns newest-first (top-most child first); the
            % newest line carries alpha == 1 (stashed in UserData since
            % R2023a's Line.Color is 3-element RGB only).
            newest = lines(1);
            ud = newest.UserData;
            testCase.assertTrue(isstruct(ud) && isfield(ud, 'alpha'), ...
                'Expected UserData.alpha to be set by addTrial.');
            testCase.verifyEqual(ud.alpha, 1.0, 'AbsTol', 1e-9);
        end

        function testYLabelFlipsOnMode(testCase)
            y = Round3_TrialPlotPanelTest.sineTrace(testCase.Fs);
            testCase.Panel.addTrial(y, testCase.Fs, "VC");

            ax = findall(testCase.Panel.Panel, 'Type', 'axes');
            testCase.assertNotEmpty(ax);
            testCase.verifySubstring(ax(1).YLabel.String, 'pA');

            testCase.Panel.addTrial(y, testCase.Fs, "IC");
            ax = findall(testCase.Panel.Panel, 'Type', 'axes');
            testCase.verifySubstring(ax(1).YLabel.String, 'mV');
        end

        function testClearRemovesAllLines(testCase)
            y = Round3_TrialPlotPanelTest.sineTrace(testCase.Fs);
            for k = 1:3
                testCase.Panel.addTrial(y, testCase.Fs, "VC");
            end
            testCase.Panel.clear();
            lines = findall(testCase.Panel.Panel, 'Type', 'line');
            testCase.verifyEqual(numel(lines), 0);
        end

        function testXAxisCoversTwoHundredMs(testCase)
            y = Round3_TrialPlotPanelTest.sineTrace(testCase.Fs);
            testCase.Panel.addTrial(y, testCase.Fs, "VC");

            ax = findall(testCase.Panel.Panel, 'Type', 'axes');
            xl = ax(1).XLim;
            testCase.verifyEqual(xl(2), 200, 'AbsTol', 1.0);
        end

    end
end
