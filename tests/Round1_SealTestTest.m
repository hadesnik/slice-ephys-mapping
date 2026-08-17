classdef Round1_SealTestTest < matlab.unittest.TestCase
    % Round1_SealTestTest  Verifies the seal-test segment generator.

    methods (Test)
        function testVcDefaultShapeAndAmplitude(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            [ao0, epochs] = patchclamp.protocol.SealTest.build(cfg.sealTest, "VC", 20000);

            tc.verifyEqual(numel(ao0), 4000);
            tc.verifyEqual(epochs.preSamples, 1000);
            tc.verifyEqual(epochs.stepSamples, 2000);
            tc.verifyEqual(epochs.postSamples, 1000);
            tc.verifyEqual(epochs.stepStartIdx, 1001);
            tc.verifyEqual(epochs.stepEndIdx, 3000);

            tc.verifyEqual(ao0(1:1000), zeros(1000, 1));
            tc.verifyEqual(unique(ao0(1001:3000)), -5);
            tc.verifyEqual(ao0(3001:4000), zeros(1000, 1));
        end

        function testIcDefaultUsesIcAmplitude(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            [ao0, epochs] = patchclamp.protocol.SealTest.build(cfg.sealTest, "IC", 20000);

            tc.verifyEqual(unique(ao0(epochs.stepStartIdx:epochs.stepEndIdx)), -100);
            tc.verifyEqual(ao0(1:epochs.preSamples), zeros(epochs.preSamples, 1));
            tc.verifyEqual(ao0(epochs.stepEndIdx + 1:end), zeros(epochs.postSamples, 1));
        end

        function testSamplesPerEpochSumsToTotal(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            [ao0, epochs] = patchclamp.protocol.SealTest.build(cfg.sealTest, "VC", 20000);
            tc.verifyEqual(epochs.preSamples + epochs.stepSamples + epochs.postSamples, ...
                numel(ao0));
        end

        function testDifferentSampleRateScales(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            [ao0_10k, epochs10k] = patchclamp.protocol.SealTest.build(cfg.sealTest, "VC", 10000);
            tc.verifyEqual(numel(ao0_10k), 2000);
            tc.verifyEqual(epochs10k.preSamples, 500);
            tc.verifyEqual(epochs10k.stepSamples, 1000);
            tc.verifyEqual(epochs10k.postSamples, 500);
            tc.verifyEqual(epochs10k.stepStartIdx, 501);
            tc.verifyEqual(epochs10k.stepEndIdx, 1500);

            [ao0_40k, epochs40k] = patchclamp.protocol.SealTest.build(cfg.sealTest, "VC", 40000);
            tc.verifyEqual(numel(ao0_40k), 8000);
            tc.verifyEqual(epochs40k.stepSamples, 4000);
        end

        function testCustomDurations(tc)
            sealTest = struct( ...
                'amplitudeVcMv', -10, ...
                'amplitudeIcPa', -200, ...
                'preMs',         25, ...
                'stepMs',        50, ...
                'postMs',        25);
            [ao0, epochs] = patchclamp.protocol.SealTest.build(sealTest, "VC", 20000);
            tc.verifyEqual(epochs.preSamples, 500);
            tc.verifyEqual(epochs.stepSamples, 1000);
            tc.verifyEqual(epochs.postSamples, 500);
            tc.verifyEqual(numel(ao0), 2000);
            tc.verifyEqual(unique(ao0(epochs.stepStartIdx:epochs.stepEndIdx)), -10);
        end

        function testInvalidModeErrors(tc)
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            tc.verifyError(@() patchclamp.protocol.SealTest.build(cfg.sealTest, "I=0", 20000), ...
                ?MException);
        end

        function testMissingFieldErrors(tc)
            bad = struct('amplitudeVcMv', -5, 'amplitudeIcPa', -100, 'preMs', 50, 'stepMs', 100);
            tc.verifyError(@() patchclamp.protocol.SealTest.build(bad, "VC", 20000), ...
                "patchclamp:config:TrialConfig:sealTestMissingField");
        end
    end
end
