classdef Round1_TrialTest < matlab.unittest.TestCase
    % Round1_TrialTest  Verifies Trial.compose stitches seal-test + pause + stim.

    methods (Test)
        function testDefaultVcTrialNoStim(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            [ao0, ao2, layout] = patchclamp.protocol.Trial.compose(cfg, "VC");

            tc.verifyEqual(numel(ao0), 20000);
            tc.verifyEqual(numel(ao2), 20000);

            % Seal test occupies samples 1..4000.
            tc.verifyEqual(layout.sealTestStartIdx, 1);
            tc.verifyEqual(layout.sealTestEndIdx, 4000);
            tc.verifyEqual(layout.sealTestStepStartIdx, 1001);
            tc.verifyEqual(layout.sealTestStepEndIdx, 3000);

            % Stim window starts at sample 6001 (300 ms at 20 kHz).
            tc.verifyEqual(layout.stimulusWindowStartIdx, 6001);
            tc.verifyEqual(layout.stimulusWindowEndIdx, 20000);

            tc.verifyEqual(unique(ao0(1001:3000)), -5);
            tc.verifyEqual(ao0(4001:20000), zeros(16000, 1));   % pause + empty stim window
            tc.verifyEqual(ao2, zeros(20000, 1));
        end

        function testCommandStimGoesIntoStimWindow(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            cfg.commandStim = struct('pulseDurationMs', 5, 'amplitude', 30, ...
                                     'frequencyHz', 20, 'nPulses', 10);

            [ao0, ~, layout] = patchclamp.protocol.Trial.compose(cfg, "VC");

            % Seal test still intact at start.
            tc.verifyEqual(unique(ao0(1001:3000)), -5);

            % Pause samples 4001..6000 are zero.
            tc.verifyEqual(ao0(4001:6000), zeros(2000, 1));

            % Stim window starts at 6001. First pulse: samples 6001..6100 at 30.
            tc.verifyEqual(unique(ao0(6001:6100)), 30);
            tc.verifyEqual(unique(ao0(6101:7000)), 0);
            % Last pulse onset: 6001 + 9*1000 = 15001, off at 15100.
            tc.verifyEqual(unique(ao0(15001:15100)), 30);
            tc.verifyEqual(unique(ao0(15101:20000)), 0);

            tc.verifyEqual(layout.stimulusWindowStartIdx, 6001);
        end

        function testOptoGoesOnlyOnAo2(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            cfg.opto = struct('pulseDurationMs', 5, 'amplitude', 50, ...
                              'frequencyHz', 20, 'nPulses', 10);

            [ao0, ao2, ~] = patchclamp.protocol.Trial.compose(cfg, "VC");

            % AO0 still has the seal test only.
            tc.verifyEqual(unique(ao0(1001:3000)), -5);
            tc.verifyEqual(ao0(4001:20000), zeros(16000, 1));

            % AO2 zero before the stim window.
            tc.verifyEqual(ao2(1:6000), zeros(6000, 1));
            % AO2 first opto pulse at 50 percent -> 2.5 V.
            tc.verifyEqual(unique(ao2(6001:6100)), 2.5, "AbsTol", 1e-12);
            tc.verifyEqual(unique(ao2(6101:7000)), 0);
        end

        function testEmptyOptoGivesZeroAo2(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            cfg.opto = [];
            [~, ao2, ~] = patchclamp.protocol.Trial.compose(cfg, "VC");
            tc.verifyEqual(ao2, zeros(20000, 1));
        end

        function testIcModeUsesIcSealTestAmplitude(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            [ao0, ~, layout] = patchclamp.protocol.Trial.compose(cfg, "IC");
            tc.verifyEqual(unique(ao0(layout.sealTestStepStartIdx:layout.sealTestStepEndIdx)), -100);
        end

        function testIcCommandStimFlowsThroughInPa(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            cfg.commandStim = struct('pulseDurationMs', 5, 'amplitude', -50, ...
                                     'frequencyHz', 20, 'nPulses', 4);
            [ao0, ~, layout] = patchclamp.protocol.Trial.compose(cfg, "IC");
            firstPulse = ao0(layout.stimulusWindowStartIdx:layout.stimulusWindowStartIdx + 99);
            tc.verifyEqual(unique(firstPulse), -50);
        end

        function testLayoutConsistentAcrossModes(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            [~, ~, layoutVc] = patchclamp.protocol.Trial.compose(cfg, "VC");
            [~, ~, layoutIc] = patchclamp.protocol.Trial.compose(cfg, "IC");
            tc.verifyEqual(layoutVc, layoutIc);
        end

        function testCommandStimOverrunsWindowErrors(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            % 50 pulses at 20 Hz -> 2.5 s, window = 0.7 s -> error.
            cfg.commandStim = struct('pulseDurationMs', 5, 'amplitude', 30, ...
                                     'frequencyHz', 20, 'nPulses', 50);
            tc.verifyError(@() patchclamp.protocol.Trial.compose(cfg, "VC"), ...
                "patchclamp:config:PulseTrainConfig:windowTooShort");
        end

        function testInvalidModeErrors(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            tc.verifyError(@() patchclamp.protocol.Trial.compose(cfg, "I=0"), ?MException);
        end

        function testNoUnitsConversionForCommandPath(tc)
            % Cell-units invariant: ao0 contains the user's amplitude verbatim.
            % If anyone wired the conversion path in, the value would be in volts.
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            cfg.commandStim = struct('pulseDurationMs', 5, 'amplitude', 12.5, ...
                                     'frequencyHz', 20, 'nPulses', 2);
            [ao0, ~, layout] = patchclamp.protocol.Trial.compose(cfg, "VC");
            firstPulse = ao0(layout.stimulusWindowStartIdx:layout.stimulusWindowStartIdx + 99);
            tc.verifyEqual(unique(firstPulse), 12.5);
        end
    end
end
