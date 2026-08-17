classdef UnitsTest < matlab.unittest.TestCase
    % UnitsTest  Verifies the four cell <-> DAQ-volts conversions in
    % patchclamp.analysis.Units against the FakeTelegraph default gain.

    properties (Constant)
        % FakeTelegraph default gain (matches contract (3) and Units.m header).
        DefaultGain = struct( ...
            'commandVcMvPerV',   20, ...
            'commandIcPaPerV',   400, ...
            'scaledVcPaPerV',    1000, ...
            'scaledIcMvPerMv',   20);
        Tol = 1e-12;
    end

    methods (Test)
        function testVcCommandNegFiveMv(tc)
            v = patchclamp.analysis.Units.commandCellToDaqVolts(-5, "VC", tc.DefaultGain);
            tc.verifyEqual(v, -0.25, "AbsTol", tc.Tol);
        end

        function testIcCommandNegHundredPa(tc)
            v = patchclamp.analysis.Units.commandCellToDaqVolts(-100, "IC", tc.DefaultGain);
            tc.verifyEqual(v, -0.25, "AbsTol", tc.Tol);
        end

        function testVcScaledOneVoltIsOneNanoamp(tc)
            % 1 V at AI -> 1000 pA at the cell (i.e. 1 nA).
            cellValue = patchclamp.analysis.Units.scaledDaqVoltsToCell(1, "VC", tc.DefaultGain);
            tc.verifyEqual(cellValue, 1000, "AbsTol", tc.Tol);
        end

        function testIcScaledOneVoltIsFiftyMv(tc)
            % 1 V at AI -> 50 mV at the cell (gain ratio is 20 mV/mV).
            cellValue = patchclamp.analysis.Units.scaledDaqVoltsToCell(1, "IC", tc.DefaultGain);
            tc.verifyEqual(cellValue, 50, "AbsTol", tc.Tol);
        end

        function testRoundTripCommandVc(tc)
            input = [-10, -5, 0, 5, 10];
            volts = patchclamp.analysis.Units.commandCellToDaqVolts(input, "VC", tc.DefaultGain);
            back  = patchclamp.analysis.Units.commandDaqVoltsToCell(volts, "VC", tc.DefaultGain);
            tc.verifyEqual(back, input, "AbsTol", tc.Tol);
        end

        function testRoundTripCommandIc(tc)
            input = [-200, -100, 0, 100, 200];
            volts = patchclamp.analysis.Units.commandCellToDaqVolts(input, "IC", tc.DefaultGain);
            back  = patchclamp.analysis.Units.commandDaqVoltsToCell(volts, "IC", tc.DefaultGain);
            tc.verifyEqual(back, input, "AbsTol", tc.Tol);
        end

        function testRoundTripScaledVc(tc)
            inputPa = [-500, -100, 0, 250, 1000];
            volts = patchclamp.analysis.Units.scaledCellToDaqVolts(inputPa, "VC", tc.DefaultGain);
            back  = patchclamp.analysis.Units.scaledDaqVoltsToCell(volts, "VC", tc.DefaultGain);
            tc.verifyEqual(back, inputPa, "AbsTol", tc.Tol);
        end

        function testRoundTripScaledIc(tc)
            inputMv = [-80, -65, -40, 0, 30];
            volts = patchclamp.analysis.Units.scaledCellToDaqVolts(inputMv, "IC", tc.DefaultGain);
            back  = patchclamp.analysis.Units.scaledDaqVoltsToCell(volts, "IC", tc.DefaultGain);
            tc.verifyEqual(back, inputMv, "AbsTol", tc.Tol);
        end

        function testInvalidModeErrors(tc)
            tc.verifyError(@() patchclamp.analysis.Units.commandCellToDaqVolts(0, "FOO", tc.DefaultGain), ...
                ?MException);
            tc.verifyError(@() patchclamp.analysis.Units.commandDaqVoltsToCell(0, "FOO", tc.DefaultGain), ...
                ?MException);
            tc.verifyError(@() patchclamp.analysis.Units.scaledDaqVoltsToCell(0, "FOO", tc.DefaultGain), ...
                ?MException);
            tc.verifyError(@() patchclamp.analysis.Units.scaledCellToDaqVolts(0, "FOO", tc.DefaultGain), ...
                ?MException);
        end
    end
end
