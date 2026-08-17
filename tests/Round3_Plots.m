classdef Round3_Plots < matlab.unittest.TestCase
    % Round3_Plots  End-to-end tests for the Round 3a plotting panels.
    %
    % Covers patchclamp.gui.TrialPlotPanel and patchclamp.gui.TrendPlotsPanel
    % via the attachRunner / onTrialFinished / reset contract documented in
    % the agent prompt. ExperimentRunner.TrialFinished carries no custom
    % EventData; the panel's onTrialFinished reads lastTrialResult off the
    % event's Source handle.
    %
    % To drive onTrialFinished without standing up a full ExperimentRunner
    % we use one of two paths:
    %   (a) a real listener path: the TestCase itself declares a
    %       TrialFinished event (handle classes can do that) and serves
    %       as the runner. attachRunner is exercised end-to-end this way.
    %   (b) a direct call: synthesize a struct duck-typing event-data
    %       and call panel.onTrialFinished(ev) directly. This isolates
    %       the callback from MATLAB's event dispatch.
    %
    % MATLAB forbids two classdef blocks per file, so we cannot embed a
    % FakeRunner classdef alongside this one -- using the TestCase as the
    % event source is the cheapest equivalent.
    %
    % Runs headlessly: uifigure with 'Visible','off'. Each test creates its
    % own figure in TestMethodSetup and closes it in teardown.

    events
        TrialFinished
    end

    properties
        Fig
        lastTrialResult struct = struct()
    end

    methods (TestMethodSetup)
        function makeFigure(testCase)
            testCase.Fig = uifigure('Visible', 'off');
            testCase.lastTrialResult = struct();
        end
    end

    methods (TestMethodTeardown)
        function closeFigure(testCase)
            if ~isempty(testCase.Fig) && isvalid(testCase.Fig)
                close(testCase.Fig);
            end
        end
    end

    methods (Test)

        % --------- TrialPlotPanel -------------------------------------------

        function testTrialPanelConstructs(testCase)
            panel = patchclamp.gui.TrialPlotPanel(testCase.Fig);
            testCase.verifyClass(panel, 'patchclamp.gui.TrialPlotPanel');
            testCase.verifyTrue(isvalid(panel.Panel));
        end

        function testTrialOverlayCappedAtFive(testCase)
            % Decision A6: at most 5 lines retained.
            panel = patchclamp.gui.TrialPlotPanel(testCase.Fig);
            panel.attachRunner(testCase);

            for k = 1:8
                testCase.fireTrial(testCase.synthVcTrial(k));
            end

            lines = findall(panel.Panel, 'Type', 'line');
            testCase.verifyEqual(numel(lines), 5, ...
                'Trial overlay must cap at 5 lines (decision A6).');
        end

        function testNewestLineIsFullOpacity(testCase)
            panel = patchclamp.gui.TrialPlotPanel(testCase.Fig);
            panel.attachRunner(testCase);

            for k = 1:3
                testCase.fireTrial(testCase.synthVcTrial(k));
            end

            lines = findall(panel.Panel, 'Type', 'line');
            % findall returns newest-first; the newest line carries alpha=1
            % stashed in UserData (R2023a Line.Color is 3-element RGB only).
            newest = lines(1);
            ud = newest.UserData;
            testCase.assertTrue(isstruct(ud) && isfield(ud, 'alpha'));
            testCase.verifyEqual(ud.alpha, 1.0, 'AbsTol', 1e-9);
        end

        function testTrialPanelYLabelFollowsMode(testCase)
            panel = patchclamp.gui.TrialPlotPanel(testCase.Fig);
            panel.attachRunner(testCase);

            testCase.fireTrial(testCase.synthVcTrial(1));
            ax = findall(panel.Panel, 'Type', 'axes');
            testCase.verifySubstring(ax(1).YLabel.String, 'pA');

            testCase.fireTrial(testCase.synthIcTrial(2));
            ax = findall(panel.Panel, 'Type', 'axes');
            testCase.verifySubstring(ax(1).YLabel.String, 'mV');
        end

        function testTrialPanelClearsOnModeFlip(testCase)
            % Mixed-mode overlay is ambiguous (different Y units), so a mode
            % flip starts a fresh overlay.
            panel = patchclamp.gui.TrialPlotPanel(testCase.Fig);
            panel.attachRunner(testCase);

            for k = 1:3
                testCase.fireTrial(testCase.synthVcTrial(k));
            end
            testCase.verifyEqual( ...
                numel(findall(panel.Panel, 'Type', 'line')), 3);

            testCase.fireTrial(testCase.synthIcTrial(4));
            % After mode flip, only the new (IC) line should remain.
            testCase.verifyEqual( ...
                numel(findall(panel.Panel, 'Type', 'line')), 1);
        end

        function testTrialPanelResetClearsAll(testCase)
            panel = patchclamp.gui.TrialPlotPanel(testCase.Fig);
            panel.attachRunner(testCase);

            for k = 1:4
                testCase.fireTrial(testCase.synthVcTrial(k));
            end
            testCase.verifyEqual( ...
                numel(findall(panel.Panel, 'Type', 'line')), 4);

            panel.reset();
            testCase.verifyEqual( ...
                numel(findall(panel.Panel, 'Type', 'line')), 0);
        end

        % --------- TrendPlotsPanel ------------------------------------------

        function testTrendPanelConstructs(testCase)
            panel = patchclamp.gui.TrendPlotsPanel(testCase.Fig);
            testCase.verifyClass(panel, 'patchclamp.gui.TrendPlotsPanel');
            testCase.verifyTrue(isvalid(panel.Panel));
            % Three axes (Rs, Ri, Holding).
            axList = findall(panel.Panel, 'Type', 'axes');
            testCase.verifyEqual(numel(axList), 3);
        end

        function testTrendPanelVcAddsToAllThreeAxes(testCase)
            panel = patchclamp.gui.TrendPlotsPanel(testCase.Fig);
            panel.attachRunner(testCase);

            testCase.fireTrial(testCase.synthVcTrial(1));

            [axRs, axRi, axHold] = testCase.locateTrendAxes(panel);
            testCase.verifyEqual(numel(findall(axRs,   'Type', 'line')), 1);
            testCase.verifyEqual(numel(findall(axRi,   'Type', 'line')), 1);
            testCase.verifyEqual(numel(findall(axHold, 'Type', 'line')), 1);
        end

        function testTrendPanelRsGapInIc(testCase)
            % Rs is meaningless in IC: IC trials add no Rs point.
            panel = patchclamp.gui.TrendPlotsPanel(testCase.Fig);
            panel.attachRunner(testCase);

            testCase.fireTrial(testCase.synthVcTrial(1));
            testCase.fireTrial(testCase.synthIcTrial(2));
            testCase.fireTrial(testCase.synthIcTrial(3));
            testCase.fireTrial(testCase.synthVcTrial(4));

            [axRs, axRi, ~] = testCase.locateTrendAxes(panel);
            rsLines = findall(axRs, 'Type', 'line');
            testCase.verifyEqual(numel(rsLines), 2, ...
                'Only the two VC trials should contribute Rs points.');
            % Ri tracks all four.
            testCase.verifyEqual( ...
                numel(findall(axRi, 'Type', 'line')), 4);
        end

        function testTrendPanelHoldingLabelFlipsPerMode(testCase)
            panel = patchclamp.gui.TrendPlotsPanel(testCase.Fig);
            panel.attachRunner(testCase);

            testCase.fireTrial(testCase.synthVcTrial(1));
            [~, ~, axHold] = testCase.locateTrendAxes(panel);
            testCase.verifySubstring(axHold.YLabel.String, 'Holding (pA)');

            testCase.fireTrial(testCase.synthIcTrial(2));
            [~, ~, axHold] = testCase.locateTrendAxes(panel);
            testCase.verifySubstring(axHold.YLabel.String, 'Vrest (mV)');
        end

        function testTrendPanelRsTitleFlagsIc(testCase)
            % While in IC, the Rs axes title indicates Rs is unavailable.
            panel = patchclamp.gui.TrendPlotsPanel(testCase.Fig);
            panel.attachRunner(testCase);

            testCase.fireTrial(testCase.synthIcTrial(1));
            [axRs, ~, ~] = testCase.locateTrendAxes(panel);
            testCase.verifySubstring(axRs.Title.String, 'IC');
        end

        function testTrendPanelResetClearsHistoryAndCounter(testCase)
            panel = patchclamp.gui.TrendPlotsPanel(testCase.Fig);
            panel.attachRunner(testCase);

            for k = 1:3
                testCase.fireTrial(testCase.synthVcTrial(k));
            end
            panel.reset();

            [axRs, axRi, axHold] = testCase.locateTrendAxes(panel);
            testCase.verifyEqual(numel(findall(axRs,   'Type', 'line')), 0);
            testCase.verifyEqual(numel(findall(axRi,   'Type', 'line')), 0);
            testCase.verifyEqual(numel(findall(axHold, 'Type', 'line')), 0);

            % Next trial after reset should land at x=1.
            testCase.fireTrial(testCase.synthVcTrial(99));
            [~, axRi, ~] = testCase.locateTrendAxes(panel);
            line = findall(axRi, 'Type', 'line');
            testCase.verifyEqual(line(1).XData(1), 1, 'AbsTol', 1e-9);
        end

        function testOnTrialFinishedDirectCall(testCase)
            % Exercise the callback directly with a synthesized event-data
            % object, independent of MATLAB's event dispatch.
            panel = patchclamp.gui.TrendPlotsPanel(testCase.Fig);
            testCase.lastTrialResult = testCase.synthVcTrial(1);

            ev = struct('Source', testCase);   % duck-typed event-data substitute
            panel.onTrialFinished(ev);

            [~, axRi, ~] = testCase.locateTrendAxes(panel);
            testCase.verifyEqual( ...
                numel(findall(axRi, 'Type', 'line')), 1);
        end

    end

    methods (Access = private)
        function fireTrial(testCase, tr)
            testCase.lastTrialResult = tr;
            notify(testCase, "TrialFinished");
        end
    end

    methods (Static, Access = private)
        function tr = synthVcTrial(idx)
            fs = 20000;
            n  = round(0.5 * fs);
            t  = (0:n-1)' / fs;
            ai = 5 + 2 * sin(2*pi*10*t);   % pA-ish trace, arbitrary shape
            tr = struct( ...
                'aiCellUnits',        ai, ...
                'aoCommandCellUnits', zeros(n,1), ...
                'aoLedVolts',         zeros(n,1), ...
                'rsMohm',             10 + double(idx) * 0.1, ...
                'riMohm',             200 + double(idx), ...
                'holding',            -40 - double(idx), ...
                'holdingUnit',        "pA", ...
                'mode',               "VC", ...
                'sampleRateHz',       fs, ...
                'timestamp',          "2026-01-01T00:00:00", ...
                'gainSnapshot',       struct(), ...
                'trialIndex',         uint32(idx));
        end

        function tr = synthIcTrial(idx)
            fs = 20000;
            n  = round(0.5 * fs);
            t  = (0:n-1)' / fs;
            ai = -65 + 0.5 * sin(2*pi*5*t);   % mV-ish trace
            tr = struct( ...
                'aiCellUnits',        ai, ...
                'aoCommandCellUnits', zeros(n,1), ...
                'aoLedVolts',         zeros(n,1), ...
                'rsMohm',             NaN, ...
                'riMohm',             180 + double(idx), ...
                'holding',            -65 - double(idx) * 0.1, ...
                'holdingUnit',        "mV", ...
                'mode',               "IC", ...
                'sampleRateHz',       fs, ...
                'timestamp',          "2026-01-01T00:00:00", ...
                'gainSnapshot',       struct(), ...
                'trialIndex',         uint32(idx));
        end

        function [axRs, axRi, axHold] = locateTrendAxes(panelObj)
            % Locate the three trend axes by inspecting their YLabel
            % strings -- robust against findall's child ordering.
            axList = findall(panelObj.Panel, 'Type', 'axes');
            axRs = []; axRi = []; axHold = [];
            for k = 1:numel(axList)
                ylab = axList(k).YLabel.String;
                if contains(ylab, 'Series')
                    axRs = axList(k);
                elseif contains(ylab, 'Input')
                    axRi = axList(k);
                elseif contains(ylab, 'Holding') || contains(ylab, 'Vrest')
                    axHold = axList(k);
                end
            end
        end
    end
end
