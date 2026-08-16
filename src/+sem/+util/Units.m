classdef Units
    %Units Mode-aware conversions between cell units and DAQ volts.
    %   Lifted from the lab's whole-cell patch software (patchclamp.analysis.Units)
    %   and restyled for this repo. There are two physical signal paths, each
    %   with its own scaling:
    %
    %     1. Command path (DAQ AO -> 700B EXT COMMAND)
    %          VC: gain.commandVcMvPerV  mV per V at the DAQ AO  (typ. 20)
    %          IC: gain.commandIcPaPerV  pA per V at the DAQ AO  (typ. 400)
    %        These are PHYSICAL CONSTANTS of the 700B EXT COMMAND input.
    %
    %     2. Scaled-output path (700B SCALED OUTPUT -> DAQ AI)
    %          VC: gain.scaledVcPaPerV   pA per V at the AI       (typ. 1000)
    %          IC: gain.scaledIcMvPerMv  mV at the AI per mV at the cell (typ. 20)
    %        These are set on the front panel / telegraph; snapshot them into
    %        every trial's metadata.ephys.gains.
    %
    %   All conversions live in this file so they can be audited in one place.
    %   Anywhere else in the MATLAB code that does its own conversion is a bug.
    %   (The Python analysis package mirrors these in units.py — change both
    %   together.)

    methods (Static)
        function gain = gainFromConfig(ephysCfg)
            %gainFromConfig Build the gain struct from a config ephys section.
            gain = struct( ...
                'commandVcMvPerV', sem.util.configField(ephysCfg, 'commandVcMvPerV', 20), ...
                'commandIcPaPerV', sem.util.configField(ephysCfg, 'commandIcPaPerV', 400), ...
                'scaledVcPaPerV',  sem.util.configField(ephysCfg, 'scaledVcPaPerV', 1000), ...
                'scaledIcMvPerMv', sem.util.configField(ephysCfg, 'scaledIcMvPerMv', 20));
        end

        function volts = commandCellToDaqVolts(cellValue, mode, gain)
            %commandCellToDaqVolts Cell-unit command (mV in VC, pA in IC) -> DAQ AO volts.
            sem.util.Units.checkMode(mode);
            if strcmp(char(mode), 'VC')
                volts = cellValue ./ gain.commandVcMvPerV;
            else
                volts = cellValue ./ gain.commandIcPaPerV;
            end
        end

        function cellValue = commandDaqVoltsToCell(volts, mode, gain)
            %commandDaqVoltsToCell Inverse of commandCellToDaqVolts.
            sem.util.Units.checkMode(mode);
            if strcmp(char(mode), 'VC')
                cellValue = volts .* gain.commandVcMvPerV;
            else
                cellValue = volts .* gain.commandIcPaPerV;
            end
        end

        function cellValue = scaledDaqVoltsToCell(volts, mode, gain)
            %scaledDaqVoltsToCell AI sample (DAQ volts) -> cell units (pA in VC, mV in IC).
            %   IC ratio is dimensionless (mV out per mV at the cell); AI is in
            %   volts, so *1000 converts V to mV before dividing.
            sem.util.Units.checkMode(mode);
            if strcmp(char(mode), 'VC')
                cellValue = volts .* gain.scaledVcPaPerV;
            else
                cellValue = volts .* (1000 ./ gain.scaledIcMvPerMv);
            end
        end

        function volts = scaledCellToDaqVolts(cellValue, mode, gain)
            %scaledCellToDaqVolts Inverse of scaledDaqVoltsToCell.
            %   Used by MockEphysDAQ to synthesise an AI trace in volts from a
            %   known cell-unit ground truth.
            sem.util.Units.checkMode(mode);
            if strcmp(char(mode), 'VC')
                volts = cellValue ./ gain.scaledVcPaPerV;
            else
                volts = cellValue .* (gain.scaledIcMvPerMv ./ 1000);
            end
        end
    end

    methods (Static, Access = private)
        function checkMode(mode)
            if ~ismember(char(mode), {'VC', 'IC'})
                error('sem:util:Units:badMode', ...
                    'mode must be ''VC'' or ''IC''; got ''%s''.', char(mode));
            end
        end
    end
end
