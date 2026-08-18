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

    % The amplifier also owns the HOLDING command. The experimenter sets it on
    % the Commander; software reads it so it can be displayed and recorded, and
    % writes it only when the operator explicitly asks (e.g. the -70 / +10 mV
    % buttons for the E and I blocks). Software must never silently add holding
    % to the analog-out on top of what the Commander is already applying.
    %
    % getHolding / setHolding are concrete here and error by default, so a
    % telegraph with no link to the Commander fails loudly rather than
    % pretending to know the holding level.

    events
        ModeChanged    % EventData carries new mode "VC" or "IC".
        GainChanged    % EventData carries the new gain struct (fields above).
        HoldingChanged % Listener reads getHolding() off the source.
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

    methods
        function holdingMv = getHolding(obj) %#ok<STOUT,MANU>
            %getHolding Holding command the amplifier is applying, in cell units.
            %   mV in voltage clamp, pA in current clamp. Override in a
            %   telegraph that can actually read the Commander.
            error('patchclamp:hardware:MultiClamp:holdingNotSupported', ...
                ['This telegraph cannot read the amplifier holding. Use a ' ...
                 'telegraph connected to the MultiClamp Commander.']);
        end

        function setHolding(obj, holdingMv) %#ok<INUSD,MANU>
            %setHolding Command the amplifier to a new holding level.
            %   Only ever called on an explicit operator request.
            error('patchclamp:hardware:MultiClamp:holdingNotSupported', ...
                ['This telegraph cannot set the amplifier holding. Use a ' ...
                 'telegraph connected to the MultiClamp Commander.']);
        end
    end
end
