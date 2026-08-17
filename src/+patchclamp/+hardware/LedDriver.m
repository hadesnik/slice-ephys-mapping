classdef LedDriver
    % LedDriver  Linear converter between brightness percent and LED-driver AO volts.
    %
    % The LED driver is a generic 0..5 V analog-in unit; brightness is linear in
    % voltage for v1 (auto-mode decision Q7). Calibration UI is deferred to v2.

    properties (Constant)
        MIN_VOLTS = 0
        MAX_VOLTS = 5
    end

    methods (Static)
        function volts = brightnessPercentToVolts(pct)
            arguments
                pct (1,1) double {mustBeReal, mustBeFinite, mustBeGreaterThanOrEqual(pct, 0), mustBeLessThanOrEqual(pct, 100)}
            end
            volts = pct * (patchclamp.hardware.LedDriver.MAX_VOLTS / 100);
        end

        function pct = voltsToBrightnessPercent(volts)
            arguments
                volts (1,1) double {mustBeReal, mustBeFinite, ...
                    mustBeGreaterThanOrEqual(volts, 0), ...
                    mustBeLessThanOrEqual(volts, 5)}
            end
            pct = volts * (100 / patchclamp.hardware.LedDriver.MAX_VOLTS);
        end
    end
end
