classdef SmokeTest < matlab.unittest.TestCase
    % SmokeTest  Verifies that the patchclamp package resolves on macOS and that
    % the default TrialConfig passes its own validator.

    methods (Test)
        function testPackageLoadsAndDefaultTrialConfigValidates(tc)
            import patchclamp.*
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            tc.verifyEqual(cfg.mode, "VC");
            tc.verifyEqual(cfg.sampleRateHz, 20000);
            patchclamp.config.TrialConfig.validate(cfg);
        end

        function testDefaultPulseTrainValidates(tc)
            cfg = patchclamp.config.PulseTrainConfig.defaultConfig();
            patchclamp.config.PulseTrainConfig.validate(cfg);
            % 10 pulses at 20 Hz = 0.5 s, fits a 0.7 s stimulus window.
            patchclamp.config.PulseTrainConfig.validateFitsWindow(cfg, 0.7);
            tc.verifyError( ...
                @() patchclamp.config.PulseTrainConfig.validateFitsWindow(cfg, 0.4), ...
                "patchclamp:config:PulseTrainConfig:windowTooShort");
        end

        function testTrialConfigRejectsMissingField(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            cfg = rmfield(cfg, "itiSec");
            tc.verifyError(@() patchclamp.config.TrialConfig.validate(cfg), ...
                "patchclamp:config:TrialConfig:missingField");
        end

        function testTrialConfigRejectsBadMode(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            cfg.mode = "FOO";
            tc.verifyError(@() patchclamp.config.TrialConfig.validate(cfg), ?MException);
        end
    end
end
