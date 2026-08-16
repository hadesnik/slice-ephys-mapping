classdef test_units < matlab.unittest.TestCase
    %test_units sem.util.Units conversions: the single audited home of all
    %   cell-unit <-> DAQ-volt scaling. The Python units.py mirrors these
    %   numbers; if this file's expectations change, change both together.

    methods (Test)
        function command_vc_roundtrip(tc)
            gain = sem.util.Units.gainFromConfig(struct());
            volts = sem.util.Units.commandCellToDaqVolts(-70, 'VC', gain);
            tc.verifyEqual(volts, -3.5, 'AbsTol', 1e-12);   % -70 mV / 20 mV/V
            back = sem.util.Units.commandDaqVoltsToCell(volts, 'VC', gain);
            tc.verifyEqual(back, -70, 'AbsTol', 1e-12);
        end

        function command_ic_roundtrip(tc)
            gain = sem.util.Units.gainFromConfig(struct());
            volts = sem.util.Units.commandCellToDaqVolts(-20, 'IC', gain);
            tc.verifyEqual(volts, -0.05, 'AbsTol', 1e-12);  % -20 pA / 400 pA/V
            back = sem.util.Units.commandDaqVoltsToCell(volts, 'IC', gain);
            tc.verifyEqual(back, -20, 'AbsTol', 1e-12);
        end

        function scaled_vc_roundtrip(tc)
            gain = sem.util.Units.gainFromConfig(struct());
            cellPa = sem.util.Units.scaledDaqVoltsToCell(0.25, 'VC', gain);
            tc.verifyEqual(cellPa, 250, 'AbsTol', 1e-9);    % 0.25 V * 1000 pA/V
            volts = sem.util.Units.scaledCellToDaqVolts(cellPa, 'VC', gain);
            tc.verifyEqual(volts, 0.25, 'AbsTol', 1e-12);
        end

        function scaled_ic_roundtrip(tc)
            gain = sem.util.Units.gainFromConfig(struct());
            cellMv = sem.util.Units.scaledDaqVoltsToCell(1.3, 'IC', gain);
            tc.verifyEqual(cellMv, 65, 'AbsTol', 1e-9);     % 1.3 V * 1000 / 20
            volts = sem.util.Units.scaledCellToDaqVolts(cellMv, 'IC', gain);
            tc.verifyEqual(volts, 1.3, 'AbsTol', 1e-12);
        end

        function bad_mode_throws(tc)
            gain = sem.util.Units.gainFromConfig(struct());
            tc.verifyError(@() sem.util.Units.commandCellToDaqVolts(1, 'XX', gain), ...
                'sem:util:Units:badMode');
        end

        function gains_read_from_config(tc)
            gain = sem.util.Units.gainFromConfig(struct('scaledVcPaPerV', 500));
            cellPa = sem.util.Units.scaledDaqVoltsToCell(1, 'VC', gain);
            tc.verifyEqual(cellPa, 500, 'AbsTol', 1e-9);
        end
    end
end
