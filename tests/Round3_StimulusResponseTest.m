classdef Round3_StimulusResponseTest < matlab.unittest.TestCase
    % Round3_StimulusResponseTest
    %
    % Verifies StimulusResponsePanel crops to the stimulus window, caps the
    % overlay at 5 (decision A6), flips the Y label on mode change, and
    % handles the TrialFinished-via-attachRunner path with a layout-bearing
    % result struct.

    properties
        Figure
    end

    properties
        % Test acts as the event source for attachRunner; must be public so
        % the panel's onTrialFinished can read eventData.Source.lastTrialResult.
        lastTrialResult struct = struct()
    end

    events
        TrialFinished
    end

    methods (TestMethodSetup)
        function makeFigure(testCase)
            testCase.Figure = uifigure('Visible','off');
            testCase.addTeardown(@() delete(testCase.Figure));
        end
    end

    methods (Test)
        function testConstructsOnPlainFigure(testCase)
            p = patchclamp.gui.StimulusResponsePanel(testCase.Figure);
            testCase.verifyClass(p, "patchclamp.gui.StimulusResponsePanel");
            testCase.verifyEqual(string(p.Axes.YLabel.String), "Im (pA)");
        end

        function testCropsToStimulusWindow(testCase)
            p = patchclamp.gui.StimulusResponsePanel(testCase.Figure);
            sr = 20000;
            ai = (1:sr)';        % 1 second, value = sample index for traceability
            layout = struct( ...
                'stimulusWindowStartIdx', 5001, ...
                'stimulusWindowEndIdx',   sr);
            p.addTrial(ai, sr, "VC", layout);

            lines = findall(p.Axes, 'Type', 'line');
            testCase.assertEqual(numel(lines), 1);
            testCase.verifyEqual(numel(lines(1).YData), sr - 5001 + 1);
            % First plotted sample should be value 5001, last should be sr.
            testCase.verifyEqual(lines(1).YData(1),   5001);
            testCase.verifyEqual(lines(1).YData(end), sr);
            % X axis starts at 0 ms from stim onset.
            testCase.verifyEqual(lines(1).XData(1), 0);
        end

        function testOverlayCappedAtFive(testCase)
            p = patchclamp.gui.StimulusResponsePanel(testCase.Figure);
            sr = 10000;
            ai = zeros(sr,1);
            layout = struct('stimulusWindowStartIdx', 1001, 'stimulusWindowEndIdx', sr);
            for k = 1:7
                p.addTrial(ai + k, sr, "VC", layout);
            end
            lines = findall(p.Axes, 'Type', 'line');
            testCase.verifyEqual(numel(lines), 5);
        end

        function testModeFlipClearsOverlay(testCase)
            p = patchclamp.gui.StimulusResponsePanel(testCase.Figure);
            sr = 10000;
            layout = struct('stimulusWindowStartIdx', 1001, 'stimulusWindowEndIdx', sr);
            p.addTrial(zeros(sr,1), sr, "VC", layout);
            p.addTrial(zeros(sr,1), sr, "VC", layout);
            p.addTrial(zeros(sr,1), sr, "IC", layout);
            lines = findall(p.Axes, 'Type', 'line');
            testCase.verifyEqual(numel(lines), 1);
            testCase.verifyEqual(string(p.Axes.YLabel.String), "Vm (mV)");
        end

        function testResetClears(testCase)
            p = patchclamp.gui.StimulusResponsePanel(testCase.Figure);
            sr = 10000;
            layout = struct('stimulusWindowStartIdx', 1001, 'stimulusWindowEndIdx', sr);
            p.addTrial(zeros(sr,1), sr, "IC", layout);
            p.addTrial(zeros(sr,1), sr, "IC", layout);
            p.reset();
            lines = findall(p.Axes, 'Type', 'line');
            testCase.verifyEmpty(lines);
            testCase.verifyEqual(string(p.Axes.YLabel.String), "Im (pA)");
        end

        function testAttachRunnerFiresOnTrialFinished(testCase)
            p = patchclamp.gui.StimulusResponsePanel(testCase.Figure);
            p.attachRunner(testCase);

            sr = 10000;
            ai = (1:sr)';
            testCase.lastTrialResult = struct( ...
                'aiCellUnits',  ai, ...
                'sampleRateHz', sr, ...
                'mode',         "VC", ...
                'layout',       struct( ...
                    'stimulusWindowStartIdx', 2001, ...
                    'stimulusWindowEndIdx',   sr));
            notify(testCase, "TrialFinished");

            lines = findall(p.Axes, 'Type', 'line');
            testCase.assertEqual(numel(lines), 1);
            testCase.verifyEqual(lines(1).YData(1), 2001);
            testCase.verifyEqual(numel(lines(1).YData), sr - 2001 + 1);

            p.detachRunner();
        end

        function testMissingLayoutFieldIsHarmless(testCase)
            % onTrialFinished should silently ignore results that don't carry
            % layout (older runner builds), not throw.
            p = patchclamp.gui.StimulusResponsePanel(testCase.Figure);
            p.attachRunner(testCase);
            testCase.lastTrialResult = struct( ...
                'aiCellUnits',  zeros(100,1), ...
                'sampleRateHz', 10000, ...
                'mode',         "VC");
            % Must not error.
            notify(testCase, "TrialFinished");
            lines = findall(p.Axes, 'Type', 'line');
            testCase.verifyEmpty(lines);
            p.detachRunner();
        end
    end
end
