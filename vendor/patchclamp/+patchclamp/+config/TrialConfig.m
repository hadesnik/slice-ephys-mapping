classdef TrialConfig
    % TrialConfig  Canonical default + validator for the trial-config struct.
    %
    % Schema (architecture.md sec.7):
    %   trialConfig.trialLengthSec : double scalar, > 0
    %   trialConfig.sampleRateHz   : positive integer
    %   trialConfig.itiSec         : double scalar, >= 0
    %   trialConfig.mode           : string scalar, "VC" or "IC" (mirrored from telegraph)
    %   trialConfig.sealTest       : substruct (below)
    %   trialConfig.opto           : pulseTrainStruct or []
    %   trialConfig.commandStim    : pulseTrainStruct or []
    %
    % Seal-test substruct (claude.md invariant 5: editable only via the advanced panel):
    %   sealTest.amplitudeVcMv : double scalar, default -5
    %   sealTest.amplitudeIcPa : double scalar, default -100
    %   sealTest.preMs         : double scalar, default 50
    %   sealTest.stepMs        : double scalar, default 100
    %   sealTest.postMs        : double scalar, default 50

    methods (Static)
        function s = defaultConfig()
            sealTest = struct( ...
                'amplitudeVcMv', -5, ...
                'amplitudeIcPa', -100, ...
                'preMs',         50, ...
                'stepMs',        100, ...
                'postMs',        50);

            s = struct( ...
                'trialLengthSec', 1.0, ...
                'sampleRateHz',   20000, ...
                'itiSec',         1.0, ...
                'mode',           "VC", ...
                'sealTest',       sealTest, ...
                'opto',           [], ...
                'commandStim',    []);
        end

        function validate(s)
            arguments
                s (1,1) struct
            end

            requiredFields = ["trialLengthSec", "sampleRateHz", "itiSec", ...
                              "mode", "sealTest", "opto", "commandStim"];
            for f = requiredFields
                if ~isfield(s, f)
                    error("patchclamp:config:TrialConfig:missingField", ...
                        "Trial config is missing required field '%s'.", f);
                end
            end

            mustBeA(s.trialLengthSec, "double");
            mustBeScalarOrEmpty(s.trialLengthSec);
            mustBePositive(s.trialLengthSec);

            mustBeA(s.sampleRateHz, "double");
            mustBeScalarOrEmpty(s.sampleRateHz);
            mustBePositive(s.sampleRateHz);
            mustBeInteger(s.sampleRateHz);

            mustBeA(s.itiSec, "double");
            mustBeScalarOrEmpty(s.itiSec);
            mustBeNonnegative(s.itiSec);

            modeStr = string(s.mode);
            mustBeMember(modeStr, ["VC", "IC"]);

            patchclamp.config.TrialConfig.validateSealTest(s.sealTest);

            if ~isempty(s.opto)
                patchclamp.config.PulseTrainConfig.validate(s.opto);
            end
            if ~isempty(s.commandStim)
                patchclamp.config.PulseTrainConfig.validate(s.commandStim);
            end
        end

        function validateSealTest(st)
            arguments
                st (1,1) struct
            end
            required = ["amplitudeVcMv", "amplitudeIcPa", "preMs", "stepMs", "postMs"];
            for f = required
                if ~isfield(st, f)
                    error("patchclamp:config:TrialConfig:sealTestMissingField", ...
                        "Seal-test substruct is missing required field '%s'.", f);
                end
            end
            mustBeA(st.amplitudeVcMv, "double"); mustBeScalarOrEmpty(st.amplitudeVcMv); mustBeReal(st.amplitudeVcMv);
            mustBeA(st.amplitudeIcPa, "double"); mustBeScalarOrEmpty(st.amplitudeIcPa); mustBeReal(st.amplitudeIcPa);
            mustBeA(st.preMs, "double");  mustBeScalarOrEmpty(st.preMs);  mustBeNonnegative(st.preMs);
            mustBeA(st.stepMs, "double"); mustBeScalarOrEmpty(st.stepMs); mustBePositive(st.stepMs);
            mustBeA(st.postMs, "double"); mustBeScalarOrEmpty(st.postMs); mustBeNonnegative(st.postMs);
        end
    end
end
