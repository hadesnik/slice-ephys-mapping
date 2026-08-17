classdef FakeTelegraph < patchclamp.hardware.MultiClamp
    % FakeTelegraph  Programmable, in-memory MultiClamp telegraph for macOS dev/test.
    %
    % Holds a mode ("VC" / "IC") and a gain struct (schema in MultiClamp.m). The
    % setters fire ModeChanged / GainChanged events only on an actual transition
    % so listeners can de-bounce trivially.
    %
    % Event payload: MATLAB's notify() is synchronous, so listeners can read the
    % new value off the source object via getMode() / getGain() inside their
    % callback. We do not subclass event.EventData here because that would
    % require an additional file outside this agent's owned set; the source-
    % object access pattern is equivalent for our use cases (ExperimentRunner,
    % GUI mode label) and matches how the real MccTelegraph in R4 will work.
    %
    % start() and stop() are no-ops; there is nothing to poll. They exist so
    % that code wired against the abstract MultiClamp interface can be
    % exercised through the same call sites as the real MccTelegraph.

    properties (Access = private)
        CurrentMode (1,1) string
        CurrentGain (1,1) struct
    end

    methods
        function obj = FakeTelegraph(opts)
            arguments
                opts.mode (1,1) string {mustBeMember(opts.mode, ["VC", "IC"])} = "VC"
                opts.gain (1,1) struct = patchclamp.hardware.FakeTelegraph.defaultGain()
            end
            patchclamp.hardware.FakeTelegraph.validateGain(opts.gain);
            obj.CurrentMode = opts.mode;
            obj.CurrentGain = opts.gain;
        end

        function mode = getMode(obj)
            mode = obj.CurrentMode;
        end

        function gainStruct = getGain(obj)
            gainStruct = obj.CurrentGain;
        end

        function start(~)
            % No-op: the fake doesn't poll anything.
        end

        function stop(~)
            % No-op.
        end

        function setMode(obj, newMode)
            arguments
                obj
                newMode (1,1) string {mustBeMember(newMode, ["VC", "IC"])}
            end
            if newMode == obj.CurrentMode
                return;
            end
            obj.CurrentMode = newMode;
            notify(obj, "ModeChanged");
        end

        function setGain(obj, newGain)
            arguments
                obj
                newGain (1,1) struct
            end
            patchclamp.hardware.FakeTelegraph.validateGain(newGain);
            if isequal(newGain, obj.CurrentGain)
                return;
            end
            obj.CurrentGain = newGain;
            notify(obj, "GainChanged");
        end
    end

    methods (Static)
        function g = defaultGain()
            g = struct( ...
                'commandVcMvPerV', 20, ...
                'commandIcPaPerV', 400, ...
                'scaledVcPaPerV',  1000, ...
                'scaledIcMvPerMv', 20);
        end

        function validateGain(g)
            required = ["commandVcMvPerV", "commandIcPaPerV", ...
                        "scaledVcPaPerV",  "scaledIcMvPerMv"];
            for f = required
                if ~isfield(g, f)
                    error("patchclamp:hardware:FakeTelegraph:missingGainField", ...
                        "Gain struct is missing required field '%s'.", f);
                end
                v = g.(f);
                if ~(isa(v, "double") && isscalar(v) && isreal(v) && isfinite(v) && v > 0)
                    error("patchclamp:hardware:FakeTelegraph:badGainField", ...
                        "Gain field '%s' must be a positive finite real scalar double.", f);
                end
            end
        end
    end
end
