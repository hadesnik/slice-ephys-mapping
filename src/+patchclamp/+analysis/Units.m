classdef Units
    % Units  Mode-aware conversions between cell units and DAQ volts.
    %
    % There are two physical signal paths, each with its own scaling:
    %
    %   1. Command path (DAQ AO -> 700B EXT COMMAND)
    %        VC: gain.commandVcMvPerV  mV per V at the DAQ AO  (typ. 20)
    %        IC: gain.commandIcPaPerV  pA per V at the DAQ AO  (typ. 400)
    %      These are PHYSICAL CONSTANTS of the 700B EXT COMMAND input. They are not
    %      user-set on the front panel and are not read from the telegraph.
    %
    %   2. Scaled-output path (700B SCALED OUTPUT -> DAQ AI)
    %        VC: gain.scaledVcPaPerV   pA per V at the AI       (typ. 1000)
    %        IC: gain.scaledIcMvPerMv  mV at the AI per mV at the cell (typ. 20)
    %      These are READ FROM THE TELEGRAPH at runtime. The values above are
    %      FakeTelegraph defaults only (see auto-mode decisions A1-A3, tasks.md).
    %
    % All conversions live in this file so they can be audited in one place. Anywhere
    % else in the code that does its own conversion is a bug (claude.md invariant 1).
    %
    % Gain struct schema:
    %   gain = struct( ...
    %       'commandVcMvPerV',   20, ...   % DAQ-AO -> 700B command, VC mode
    %       'commandIcPaPerV',   400, ...  % DAQ-AO -> 700B command, IC mode
    %       'scaledVcPaPerV',    1000, ... % 700B SCALED OUTPUT -> DAQ-AI in VC
    %       'scaledIcMvPerMv',   20);      % 700B SCALED OUTPUT -> DAQ-AI in IC

    methods (Static)
        function volts = commandCellToDaqVolts(cellValue, mode, gain)
            % Convert a command value in cell units (mV in VC, pA in IC) to the
            % DAQ AO voltage that must be written to drive the 700B EXT COMMAND.
            %   VC: volts = cellValue / gain.commandVcMvPerV
            %   IC: volts = cellValue / gain.commandIcPaPerV
            arguments
                cellValue double {mustBeReal}
                mode (1,1) string {mustBeMember(mode, ["VC", "IC"])}
                gain (1,1) struct
            end
            if mode == "VC"
                volts = cellValue ./ gain.commandVcMvPerV;
            else
                volts = cellValue ./ gain.commandIcPaPerV;
            end
        end

        function cellValue = commandDaqVoltsToCell(volts, mode, gain)
            % Inverse of commandCellToDaqVolts. Useful for displaying back what was
            % actually sent (e.g. for a stimulus preview).
            %   VC: cellValue = volts * gain.commandVcMvPerV   (mV)
            %   IC: cellValue = volts * gain.commandIcPaPerV   (pA)
            arguments
                volts double {mustBeReal}
                mode (1,1) string {mustBeMember(mode, ["VC", "IC"])}
                gain (1,1) struct
            end
            if mode == "VC"
                cellValue = volts .* gain.commandVcMvPerV;
            else
                cellValue = volts .* gain.commandIcPaPerV;
            end
        end

        function cellValue = scaledDaqVoltsToCell(volts, mode, gain)
            % Convert an AI sample (volts at the DAQ) to cell units.
            %   VC: cellValue_pA = volts * gain.scaledVcPaPerV
            %   IC: cellValue_mV = volts * 1000 / gain.scaledIcMvPerMv
            %       The IC ratio is dimensionless (mV output per mV at the cell);
            %       AI is in volts, so the *1000 converts V to mV before dividing.
            arguments
                volts double {mustBeReal}
                mode (1,1) string {mustBeMember(mode, ["VC", "IC"])}
                gain (1,1) struct
            end
            if mode == "VC"
                cellValue = volts .* gain.scaledVcPaPerV;
            else
                cellValue = volts .* (1000 ./ gain.scaledIcMvPerMv);
            end
        end

        function volts = scaledCellToDaqVolts(cellValue, mode, gain)
            % Inverse of scaledDaqVoltsToCell. Used by FakeBackend (R1) to synthesise
            % an AI trace in volts from a known cell-unit ground truth.
            %   VC: volts = cellValue_pA / gain.scaledVcPaPerV
            %   IC: volts = cellValue_mV * gain.scaledIcMvPerMv / 1000
            arguments
                cellValue double {mustBeReal}
                mode (1,1) string {mustBeMember(mode, ["VC", "IC"])}
                gain (1,1) struct
            end
            if mode == "VC"
                volts = cellValue ./ gain.scaledVcPaPerV;
            else
                volts = cellValue .* (gain.scaledIcMvPerMv ./ 1000);
            end
        end
    end
end
