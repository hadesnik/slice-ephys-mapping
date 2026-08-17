classdef Round1_PulseTrainTest < matlab.unittest.TestCase
    % Round1_PulseTrainTest  Verifies the parametric pulse-train waveform generator.

    methods (Test)
        function testDefaultTrainAt20kHzMv(tc)
            % 10 pulses, 5 ms duration, 20 Hz: period = 50 ms, train spans 500 ms.
            % Window = 700 ms, so the last pulse ends at 495 ms, well within range.
            pt = patchclamp.config.PulseTrainConfig.defaultConfig();
            sampleRateHz = 20000;
            windowSec = 0.7;

            [wf, info] = patchclamp.protocol.PulseTrain.build(pt, sampleRateHz, windowSec, "mV");

            tc.verifyEqual(numel(wf), 14000);
            tc.verifyEqual(info.pulseOnSamples, 100);   % 5 ms * 20 kHz
            tc.verifyEqual(info.periodSamples, 1000);   % 50 ms * 20 kHz
            tc.verifyEqual(numel(info.pulseStartIdx), 10);

            % Each pulse: 100 on-samples at value 50, then 900 off-samples at 0.
            for k = 1:10
                startIdx = (k - 1) * 1000 + 1;
                endIdx = startIdx + 99;
                tc.verifyEqual(info.pulseStartIdx(k), startIdx);
                tc.verifyEqual(info.pulseEndIdx(k), endIdx);
                tc.verifyEqual(unique(wf(startIdx:endIdx)), 50);
                if k < 10
                    offStart = endIdx + 1;
                    offEnd = startIdx + 999;
                    tc.verifyEqual(unique(wf(offStart:offEnd)), 0);
                end
            end

            % Beyond last pulse: all zeros until window end (9500..14000).
            tc.verifyEqual(unique(wf(9501:14000)), 0);
        end

        function testPaCommandStimUsesAmplitudeUnchanged(tc)
            pt = struct('pulseDurationMs', 10, 'amplitude', -75, 'frequencyHz', 5, 'nPulses', 3);
            [wf, info] = patchclamp.protocol.PulseTrain.build(pt, 20000, 1.0, "pA");
            tc.verifyEqual(unique(wf(info.pulseStartIdx(1):info.pulseEndIdx(1))), -75);
        end

        function testTrainOverrunsWindowErrors(tc)
            % 50 pulses at 20 Hz -> 2.5 s required, 0.2 s window: must error clearly.
            pt = struct('pulseDurationMs', 5, 'amplitude', 50, 'frequencyHz', 20, 'nPulses', 50);
            tc.verifyError( ...
                @() patchclamp.protocol.PulseTrain.build(pt, 20000, 0.2, "mV"), ...
                "patchclamp:config:PulseTrainConfig:windowTooShort");
        end

        function testPercentConvertsViaLedDriver(tc)
            pt = struct('pulseDurationMs', 5, 'amplitude', 50, 'frequencyHz', 20, 'nPulses', 2);
            [wf, info] = patchclamp.protocol.PulseTrain.build(pt, 20000, 0.5, "percent");
            % 50 percent -> 2.5 V via LedDriver.
            tc.verifyEqual(unique(wf(info.pulseStartIdx(1):info.pulseEndIdx(1))), 2.5, "AbsTol", 1e-12);
        end

        function testPercentAboveHundredErrors(tc)
            pt = struct('pulseDurationMs', 5, 'amplitude', 200, 'frequencyHz', 20, 'nPulses', 2);
            tc.verifyError( ...
                @() patchclamp.protocol.PulseTrain.build(pt, 20000, 0.5, "percent"), ...
                ?MException);
        end

        function testInvalidAmplitudeUnitErrors(tc)
            pt = patchclamp.config.PulseTrainConfig.defaultConfig();
            tc.verifyError( ...
                @() patchclamp.protocol.PulseTrain.build(pt, 20000, 0.7, "nA"), ...
                ?MException);
        end

        function testWaveformLengthMatchesWindow(tc)
            pt = patchclamp.config.PulseTrainConfig.defaultConfig();
            [wf, info] = patchclamp.protocol.PulseTrain.build(pt, 20000, 0.7, "mV");
            tc.verifyEqual(numel(wf), info.nSamples);
            tc.verifyEqual(info.nSamples, round(0.7 * 20000));
        end

        function testValidationErrorsForBadConfig(tc)
            bad = struct('pulseDurationMs', 5, 'amplitude', 50, 'frequencyHz', 20); % no nPulses
            tc.verifyError( ...
                @() patchclamp.protocol.PulseTrain.build(bad, 20000, 0.7, "mV"), ...
                "patchclamp:config:PulseTrainConfig:missingField");
        end

        function testSinglePulseWithoutPaddingFitsExactly(tc)
            % Edge: 1 pulse at any frequency requires only 1/frequencyHz seconds.
            pt = struct('pulseDurationMs', 100, 'amplitude', 25, 'frequencyHz', 10, 'nPulses', 1);
            [wf, info] = patchclamp.protocol.PulseTrain.build(pt, 20000, 0.1, "mV");
            tc.verifyEqual(info.pulseStartIdx(1), 1);
            tc.verifyEqual(info.pulseEndIdx(1), 2000);
            tc.verifyEqual(numel(wf), 2000);
            tc.verifyEqual(unique(wf), 25);
        end
    end
end
