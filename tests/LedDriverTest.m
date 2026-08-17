classdef LedDriverTest < matlab.unittest.TestCase
    % LedDriverTest  Verifies the linear percent <-> volts mapping of LedDriver.

    properties (Constant)
        Tol = 1e-12;
    end

    methods (Test)
        function testZeroPercentIsZeroVolts(tc)
            tc.verifyEqual(patchclamp.hardware.LedDriver.brightnessPercentToVolts(0), ...
                0, "AbsTol", tc.Tol);
        end

        function testFiftyPercentIsHalfRange(tc)
            tc.verifyEqual(patchclamp.hardware.LedDriver.brightnessPercentToVolts(50), ...
                2.5, "AbsTol", tc.Tol);
        end

        function testHundredPercentIsMaxVolts(tc)
            tc.verifyEqual(patchclamp.hardware.LedDriver.brightnessPercentToVolts(100), ...
                patchclamp.hardware.LedDriver.MAX_VOLTS, "AbsTol", tc.Tol);
        end

        function testErrorBelowZero(tc)
            tc.verifyError(@() patchclamp.hardware.LedDriver.brightnessPercentToVolts(-0.01), ...
                ?MException);
        end

        function testErrorAboveHundred(tc)
            tc.verifyError(@() patchclamp.hardware.LedDriver.brightnessPercentToVolts(100.01), ...
                ?MException);
        end

        function testErrorOnNegativeVolts(tc)
            tc.verifyError(@() patchclamp.hardware.LedDriver.voltsToBrightnessPercent(-0.01), ...
                ?MException);
        end

        function testErrorOnVoltsAboveMax(tc)
            tc.verifyError(@() patchclamp.hardware.LedDriver.voltsToBrightnessPercent(5.01), ...
                ?MException);
        end

        function testRoundTripFromPercent(tc)
            samples = [0, 1, 25, 50, 75, 99, 100];
            for pct = samples
                v = patchclamp.hardware.LedDriver.brightnessPercentToVolts(pct);
                back = patchclamp.hardware.LedDriver.voltsToBrightnessPercent(v);
                tc.verifyEqual(back, pct, "AbsTol", tc.Tol);
            end
        end

        function testRoundTripFromVolts(tc)
            samples = [0, 0.5, 1.0, 2.5, 3.7, 5.0];
            for v = samples
                pct = patchclamp.hardware.LedDriver.voltsToBrightnessPercent(v);
                back = patchclamp.hardware.LedDriver.brightnessPercentToVolts(pct);
                tc.verifyEqual(back, v, "AbsTol", tc.Tol);
            end
        end
    end
end
