classdef Round3_TrendPlotsPanelTest < matlab.unittest.TestCase
    % Round3_TrendPlotsPanelTest  Tests for patchclamp.gui.TrendPlotsPanel.
    %
    % Runs headlessly: uifigure with 'Visible','off'. Each axes is located
    % via the panel's internal ordering (Rs, Ri, Holding) which is preserved
    % by findall (returns axes in reverse-creation order).

    properties
        Fig
        Panel
    end

    methods (TestMethodSetup)
        function makeFigure(testCase)
            testCase.Fig = uifigure('Visible', 'off');
            testCase.Panel = patchclamp.gui.TrendPlotsPanel(testCase.Fig);
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
        function s = vcResult(rs, ri, holdingPa)
            s = struct('rsMohm', rs, 'riMohm', ri, ...
                'holding', holdingPa, 'holdingUnit', "pA", 'mode', "VC");
        end

        function s = icResult(ri, vrestMv)
            s = struct('rsMohm', NaN, 'riMohm', ri, ...
                'holding', vrestMv, 'holdingUnit', "mV", 'mode', "IC");
        end

        function [axRs, axRi, axHold] = locateAxes(panelObj)
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

    methods (Test)

        function testAddVcResultAppendsToAllThreeAxes(testCase)
            r = Round3_TrendPlotsPanelTest.vcResult(15, 200, -50);
            testCase.Panel.addTrialResult(r);

            [axRs, axRi, axHold] = Round3_TrendPlotsPanelTest.locateAxes(testCase.Panel);
            testCase.verifyEqual(numel(findall(axRs,   'Type', 'line')), 1);
            testCase.verifyEqual(numel(findall(axRi,   'Type', 'line')), 1);
            testCase.verifyEqual(numel(findall(axHold, 'Type', 'line')), 1);
        end

        function testAddIcResultSkipsRs(testCase)
            r = Round3_TrendPlotsPanelTest.icResult(180, -65);
            testCase.Panel.addTrialResult(r);

            [axRs, axRi, axHold] = Round3_TrendPlotsPanelTest.locateAxes(testCase.Panel);
            testCase.verifyEqual(numel(findall(axRs,   'Type', 'line')), 0);
            testCase.verifyEqual(numel(findall(axRi,   'Type', 'line')), 1);
            testCase.verifyEqual(numel(findall(axHold, 'Type', 'line')), 1);
        end

        function testHoldingLabelFlipsPerMode(testCase)
            r = Round3_TrendPlotsPanelTest.vcResult(15, 200, -50);
            testCase.Panel.addTrialResult(r);
            [~, ~, axHold] = Round3_TrendPlotsPanelTest.locateAxes(testCase.Panel);
            testCase.verifySubstring(axHold.YLabel.String, 'Holding (pA)');

            r2 = Round3_TrendPlotsPanelTest.icResult(180, -65);
            testCase.Panel.addTrialResult(r2);
            [~, ~, axHold] = Round3_TrendPlotsPanelTest.locateAxes(testCase.Panel);
            testCase.verifySubstring(axHold.YLabel.String, 'Vrest (mV)');
        end

        function testClearResetsAll(testCase)
            testCase.Panel.addTrialResult( ...
                Round3_TrendPlotsPanelTest.vcResult(15, 200, -50));
            testCase.Panel.addTrialResult( ...
                Round3_TrendPlotsPanelTest.icResult(180, -65));
            testCase.Panel.clear();

            [axRs, axRi, axHold] = Round3_TrendPlotsPanelTest.locateAxes(testCase.Panel);
            testCase.verifyEqual(numel(findall(axRs,   'Type', 'line')), 0);
            testCase.verifyEqual(numel(findall(axRi,   'Type', 'line')), 0);
            testCase.verifyEqual(numel(findall(axHold, 'Type', 'line')), 0);

            % Counter reset: next add should land at x=1.
            testCase.Panel.addTrialResult( ...
                Round3_TrendPlotsPanelTest.vcResult(15, 200, -50));
            [~, axRi, ~] = Round3_TrendPlotsPanelTest.locateAxes(testCase.Panel);
            line = findall(axRi, 'Type', 'line');
            testCase.verifyEqual(line(1).XData(1), 1, 'AbsTol', 1e-9);
        end

        function testCounterAdvancesAcrossMixed(testCase)
            testCase.Panel.addTrialResult( ...
                Round3_TrendPlotsPanelTest.vcResult(15, 200, -50));
            testCase.Panel.addTrialResult( ...
                Round3_TrendPlotsPanelTest.icResult(180, -65));
            testCase.Panel.addTrialResult( ...
                Round3_TrendPlotsPanelTest.vcResult(16, 210, -52));
            testCase.Panel.addTrialResult( ...
                Round3_TrendPlotsPanelTest.icResult(190, -66));

            [~, axRi, ~] = Round3_TrendPlotsPanelTest.locateAxes(testCase.Panel);
            riLines = findall(axRi, 'Type', 'line');
            testCase.verifyEqual(numel(riLines), 4);

            xs = sort(arrayfun(@(L) L.XData(1), riLines));
            testCase.verifyEqual(xs(:)', [1 2 3 4], 'AbsTol', 1e-9);
        end

    end
end
