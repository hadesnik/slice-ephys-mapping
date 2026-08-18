classdef PulseTrainConfig
    % PulseTrainConfig  Canonical default + validator for a parametric pulse train.
    %
    % Schema (architecture.md sec.7):
    %   pulseDurationMs : double scalar, > 0
    %   amplitude       : double scalar (units are mode-dependent: pA in IC,
    %                     mV in VC for the command train; percent for opto)
    %   frequencyHz     : double scalar, > 0
    %   nPulses         : positive integer
    %   startTimeMs     : double scalar, >= 0 — onset of the first pulse from
    %                     sweep start. The acquisition GUI's stimulus panels
    %                     expose this per channel so trains can be placed
    %                     independently within a sweep.
    %   amplitudeDeltaPerSweep : double scalar — per-sweep amplitude increment
    %                     for stepped families (the F/I curve). Stepping is
    %                     applied by sem.acq.SweepRunner, not here.
    %
    % validateFitsWindow() enforces that nPulses * (1/frequencyHz) is less than or
    % equal to the available stimulus window, which is the requirement called out in
    % tasks.md Round 1 Agent B ("raise a clear error" when the train overruns).

    methods (Static)
        function s = defaultConfig()
            s = struct( ...
                'pulseDurationMs', 5, ...
                'amplitude',       50, ...
                'frequencyHz',     20, ...
                'nPulses',         10, ...
                'startTimeMs',     0, ...
                'amplitudeDeltaPerSweep', 0);
        end

        function validate(s)
            arguments
                s (1,1) struct
            end
            required = ["pulseDurationMs", "amplitude", "frequencyHz", "nPulses"];
            for f = required
                if ~isfield(s, f)
                    error("patchclamp:config:PulseTrainConfig:missingField", ...
                        "Pulse-train config is missing required field '%s'.", f);
                end
            end

            mustBeA(s.pulseDurationMs, "double");
            mustBeScalarOrEmpty(s.pulseDurationMs);
            mustBePositive(s.pulseDurationMs);

            mustBeA(s.amplitude, "double");
            mustBeScalarOrEmpty(s.amplitude);
            mustBeReal(s.amplitude);

            mustBeA(s.frequencyHz, "double");
            mustBeScalarOrEmpty(s.frequencyHz);
            mustBePositive(s.frequencyHz);

            mustBeA(s.nPulses, "double");
            mustBeScalarOrEmpty(s.nPulses);
            mustBePositive(s.nPulses);
            mustBeInteger(s.nPulses);

            % Optional: absent in configs written before the acquisition GUI
            % existed, so validate only when present rather than requiring them.
            if isfield(s, "startTimeMs")
                mustBeA(s.startTimeMs, "double");
                mustBeScalarOrEmpty(s.startTimeMs);
                mustBeNonnegative(s.startTimeMs);
                mustBeFinite(s.startTimeMs);
            end
            if isfield(s, "amplitudeDeltaPerSweep")
                mustBeA(s.amplitudeDeltaPerSweep, "double");
                mustBeScalarOrEmpty(s.amplitudeDeltaPerSweep);
                mustBeReal(s.amplitudeDeltaPerSweep);
                mustBeFinite(s.amplitudeDeltaPerSweep);
            end
        end

        function validateFitsWindow(s, stimulusWindowSec)
            arguments
                s (1,1) struct
                stimulusWindowSec (1,1) double {mustBePositive}
            end
            patchclamp.config.PulseTrainConfig.validate(s);
            requiredSec = s.nPulses * (1 / s.frequencyHz);
            if requiredSec > stimulusWindowSec
                error("patchclamp:config:PulseTrainConfig:windowTooShort", ...
                    "Pulse train requires %.4f s (%d pulses at %.2f Hz) but only %.4f s of stimulus window is available.", ...
                    requiredSec, s.nPulses, s.frequencyHz, stimulusWindowSec);
            end
        end
    end
end
