classdef (Abstract) MultiClamp < handle
    % MultiClamp  Abstract interface for a 700B telegraph source.
    %
    % Concrete implementations:
    %   patchclamp.hardware.MccTelegraph   (wraps AxMultiClampMsg.dll; Windows-only)
    %   patchclamp.hardware.FakeTelegraph  (programmable; used everywhere on macOS)
    %
    % The amplifier owns the mode (VC/IC). The GUI mirrors it; it does not command it
    % (claude.md invariant 3). Implementations poll the amplifier and fire ModeChanged
    % or GainChanged when the reported values transition.
    %
    % Gain struct schema (see sem.util.Units header for full docs):
    %   gain = struct( ...
    %       'commandVcMvPerV',   20, ...
    %       'commandIcPaPerV',   400, ...
    %       'scaledVcPaPerV',    1000, ...
    %       'scaledIcMvPerMv',   20);

    events
        ModeChanged    % EventData carries new mode "VC" or "IC".
        GainChanged    % EventData carries the new gain struct (fields above).
    end

    methods (Abstract)
        mode = getMode(obj)
            % Returns "VC" or "IC" as a string scalar.

        gainStruct = getGain(obj)
            % Returns the current gain struct (schema in this file's header).

        start(obj)
            % Begin polling the amplifier and firing ModeChanged / GainChanged events.

        stop(obj)
            % Stop polling. Safe to call repeatedly.
    end
end
