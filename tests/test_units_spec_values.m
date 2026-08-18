classdef test_units_spec_values < matlab.unittest.TestCase
    % test_units_spec_values  Verifies the four cell <-> DAQ-volts conversions in
    % sem.util.Units against the FakeTelegraph default gain.

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
            v = sem.util.Units.commandCellToDaqVolts(-5, "VC", tc.DefaultGain);
            tc.verifyEqual(v, -0.25, "AbsTol", tc.Tol);
        end

        function testIcCommandNegHundredPa(tc)
            v = sem.util.Units.commandCellToDaqVolts(-100, "IC", tc.DefaultGain);
            tc.verifyEqual(v, -0.25, "AbsTol", tc.Tol);
        end

        function testVcScaledOneVoltIsOneNanoamp(tc)
            % 1 V at AI -> 1000 pA at the cell (i.e. 1 nA).
            cellValue = sem.util.Units.scaledDaqVoltsToCell(1, "VC", tc.DefaultGain);
            tc.verifyEqual(cellValue, 1000, "AbsTol", tc.Tol);
        end

        function testIcScaledOneVoltIsFiftyMv(tc)
            % 1 V at AI -> 50 mV at the cell (gain ratio is 20 mV/mV).
            cellValue = sem.util.Units.scaledDaqVoltsToCell(1, "IC", tc.DefaultGain);
            tc.verifyEqual(cellValue, 50, "AbsTol", tc.Tol);
        end

        function testRoundTripCommandVc(tc)
            input = [-10, -5, 0, 5, 10];
            volts = sem.util.Units.commandCellToDaqVolts(input, "VC", tc.DefaultGain);
            back  = sem.util.Units.commandDaqVoltsToCell(volts, "VC", tc.DefaultGain);
            tc.verifyEqual(back, input, "AbsTol", tc.Tol);
        end

        function testRoundTripCommandIc(tc)
            input = [-200, -100, 0, 100, 200];
            volts = sem.util.Units.commandCellToDaqVolts(input, "IC", tc.DefaultGain);
            back  = sem.util.Units.commandDaqVoltsToCell(volts, "IC", tc.DefaultGain);
            tc.verifyEqual(back, input, "AbsTol", tc.Tol);
        end

        function testRoundTripScaledVc(tc)
            inputPa = [-500, -100, 0, 250, 1000];
            volts = sem.util.Units.scaledCellToDaqVolts(inputPa, "VC", tc.DefaultGain);
            back  = sem.util.Units.scaledDaqVoltsToCell(volts, "VC", tc.DefaultGain);
            tc.verifyEqual(back, inputPa, "AbsTol", tc.Tol);
        end

        function testRoundTripScaledIc(tc)
            inputMv = [-80, -65, -40, 0, 30];
            volts = sem.util.Units.scaledCellToDaqVolts(inputMv, "IC", tc.DefaultGain);
            back  = sem.util.Units.scaledDaqVoltsToCell(volts, "IC", tc.DefaultGain);
            tc.verifyEqual(back, inputMv, "AbsTol", tc.Tol);
        end

        function testInvalidModeErrors(tc)
            tc.verifyError(@() sem.util.Units.commandCellToDaqVolts(0, "FOO", tc.DefaultGain), ...
                ?MException);
            tc.verifyError(@() sem.util.Units.commandDaqVoltsToCell(0, "FOO", tc.DefaultGain), ...
                ?MException);
            tc.verifyError(@() sem.util.Units.scaledDaqVoltsToCell(0, "FOO", tc.DefaultGain), ...
                ?MException);
            tc.verifyError(@() sem.util.Units.scaledCellToDaqVolts(0, "FOO", tc.DefaultGain), ...
                ?MException);
        end
    end
end
