classdef Round1_FakeBackendTest < matlab.unittest.TestCase
    % Round1_FakeBackendTest  Validates the synthetic-trace contract of FakeBackend.
    %
    % These tests double as a worked example of the physical model: each
    % verification block references the formula in the contract spec.

    properties (Constant)
        Fs = 20000
        DurationSec = 0.2  % 200 ms is plenty for the seal-test waveform
    end

    methods (Static)
        function ao0 = flatZeroCommand(fs, durSec)
            ao0 = zeros(round(fs*durSec), 1);
        end

        function led = zeroLed(fs, durSec)
            led = zeros(round(fs*durSec), 1);
        end

        function ao0 = stepCommand(fs, durSec, amplitude, startMs, stepMs)
            N = round(fs * durSec);
            ao0 = zeros(N, 1);
            i0 = round(fs * startMs/1000) + 1;
            i1 = i0 + round(fs * stepMs/1000) - 1;
            ao0(i0:i1) = amplitude;
        end
    end

    methods (Test)
        function testConstructWithDefaults(tc)
            tele = patchclamp.hardware.FakeTelegraph();
            be = patchclamp.hardware.FakeBackend(tele);
            tc.verifyClass(be, "patchclamp.hardware.FakeBackend");
            tc.verifyEqual(be.RsMOhm,     15);
            tc.verifyEqual(be.RinputMOhm, 150);
            tc.verifyEqual(be.CmPicoF,    100);
        end

        function testConfigureTrialLengthMismatch(tc)
            tele = patchclamp.hardware.FakeTelegraph();
            be   = patchclamp.hardware.FakeBackend(tele);
            ao0 = zeros(100, 1);
            led = zeros(100, 1);
            % fs * durSec = 20000 * 0.2 = 4000 expected, got 100.
            tc.verifyError( ...
                @() be.configureTrial(ao0, led, "ai1", tc.Fs, tc.DurationSec), ...
                "patchclamp:hardware:FakeBackend:lengthMismatch");
        end

        function testConfigureTrialLedLengthMismatch(tc)
            tele = patchclamp.hardware.FakeTelegraph();
            be   = patchclamp.hardware.FakeBackend(tele);
            N = round(tc.Fs * tc.DurationSec);
            ao0 = zeros(N, 1);
            led = zeros(N-1, 1);
            tc.verifyError( ...
                @() be.configureTrial(ao0, led, "ai1", tc.Fs, tc.DurationSec), ...
                "patchclamp:hardware:FakeBackend:lengthMismatch");
        end

        function testRunBeforeConfigureErrors(tc)
            tele = patchclamp.hardware.FakeTelegraph();
            be   = patchclamp.hardware.FakeBackend(tele);
            tc.verifyError(@() be.run(), ...
                "patchclamp:hardware:FakeBackend:notConfigured");
        end

        function testVcFlatZeroBaseline(tc)
            tele = patchclamp.hardware.FakeTelegraph();  % VC
            be   = patchclamp.hardware.FakeBackend(tele, rngSeed = 1);
            N = round(tc.Fs * tc.DurationSec);
            be.configureTrial(tc.flatZeroCommand(tc.Fs, tc.DurationSec), ...
                              tc.zeroLed(tc.Fs, tc.DurationSec), ...
                              "ai1", tc.Fs, tc.DurationSec);
            ai = be.run();
            tc.verifyEqual(numel(ai), N);

            expectedBaseline = (be.VholdMv - be.VrestMv) / be.RinputMOhm * 1000;  % pA
            % With noiseRmsPaVc = 5 pA over 4000 samples, the mean should be
            % well within 3 sigma / sqrt(N) of the truth.
            stderr = be.noiseRmsPaVc / sqrt(N);
            tc.verifyEqual(mean(ai), expectedBaseline, "AbsTol", 5 * stderr);
        end

        function testVcStepRecoversRs(tc)
            % Use a large Cm so tau_s spans many samples (-> peak +/- 1 average
            % stays close to the analytic peak) and a high Rinput so the
            % steady-state arm contributes <1% to the peak. Agent C's analysis
            % will subtract the steady-state plateau before reading off Rs;
            % here we mimic that with the same subtraction so the test reflects
            % the physical contract: cap-transient peak = dV / Rs.
            tele = patchclamp.hardware.FakeTelegraph();
            be   = patchclamp.hardware.FakeBackend(tele, ...
                rngSeed = 7, RsMOhm = 15, RinputMOhm = 1500, CmPicoF = 500, ...
                noiseRmsPaVc = 1);

            stepMv  = -5;
            startMs = 50;
            stepMs  = 100;
            ao0 = tc.stepCommand(tc.Fs, tc.DurationSec, stepMv, startMs, stepMs);
            led = tc.zeroLed(tc.Fs, tc.DurationSec);
            be.configureTrial(ao0, led, "ai1", tc.Fs, tc.DurationSec);
            ai = be.run();

            iEdge = round(tc.Fs * startMs/1000) + 1;
            baseline = mean(ai(1:iEdge-1));

            % "Peak sample +/-1" -- but the cap transient is causal (zero on
            % the pre-edge sample), so we take iEdge, iEdge+1, iEdge+2 -- the
            % three samples immediately following the edge. With tau_s = 7.5
            % ms (150 samples), the transient is essentially flat across them.
            peakRegion = ai(iEdge:iEdge+2);
            peakDeflection = mean(peakRegion) - baseline;

            iSteady1 = iEdge + round(tc.Fs * stepMs/1000) - 1;
            iSteady0 = iSteady1 - round(tc.Fs * 0.030) + 1;
            steadyDeflection = mean(ai(iSteady0:iSteady1)) - baseline;
            transientPeak = peakDeflection - steadyDeflection;

            expectedTransient = stepMv / be.RsMOhm * 1000;  % pA
            tc.verifyEqual(transientPeak, expectedTransient, ...
                "RelTol", 0.10);
        end

        function testVcStepRecoversRinput(tc)
            tele = patchclamp.hardware.FakeTelegraph();
            be   = patchclamp.hardware.FakeBackend(tele, rngSeed = 3);
            stepMv  = -5;
            startMs = 50;
            stepMs  = 100;
            ao0 = tc.stepCommand(tc.Fs, tc.DurationSec, stepMv, startMs, stepMs);
            led = tc.zeroLed(tc.Fs, tc.DurationSec);
            be.configureTrial(ao0, led, "ai1", tc.Fs, tc.DurationSec);
            ai = be.run();

            iEdge = round(tc.Fs * startMs/1000) + 1;
            baseline = mean(ai(1:iEdge-1));

            % Steady-state window: last 30 ms of the 100 ms step.
            iSteady1 = iEdge + round(tc.Fs * stepMs/1000) - 1;
            iSteady0 = iSteady1 - round(tc.Fs * 0.030) + 1;
            steady   = mean(ai(iSteady0:iSteady1));

            expectedSteadyDeflection = stepMv / be.RinputMOhm * 1000;  % pA
            tc.verifyEqual(steady - baseline, expectedSteadyDeflection, ...
                "RelTol", 0.10);
        end

        function testIcFlatBaseline(tc)
            tele = patchclamp.hardware.FakeTelegraph(mode = "IC");
            be   = patchclamp.hardware.FakeBackend(tele, rngSeed = 2, IholdPa = 0);
            N = round(tc.Fs * tc.DurationSec);
            be.configureTrial(tc.flatZeroCommand(tc.Fs, tc.DurationSec), ...
                              tc.zeroLed(tc.Fs, tc.DurationSec), ...
                              "ai1", tc.Fs, tc.DurationSec);
            ai = be.run();
            expectedBaseline = be.VrestMv + be.IholdPa * be.RinputMOhm / 1000;
            stderr = be.noiseRmsMvIc / sqrt(N);
            tc.verifyEqual(mean(ai), expectedBaseline, "AbsTol", 5 * stderr);
        end

        function testIcStepDvSteadyState(tc)
            tele = patchclamp.hardware.FakeTelegraph(mode = "IC");
            be   = patchclamp.hardware.FakeBackend(tele, rngSeed = 4);
            stepPa  = -100;
            startMs = 50;
            stepMs  = 100;
            ao0 = tc.stepCommand(tc.Fs, tc.DurationSec, stepPa, startMs, stepMs);
            led = tc.zeroLed(tc.Fs, tc.DurationSec);
            be.configureTrial(ao0, led, "ai1", tc.Fs, tc.DurationSec);
            ai = be.run();

            iEdge = round(tc.Fs * startMs/1000) + 1;
            baseline = mean(ai(1:iEdge-1));
            iSteady1 = iEdge + round(tc.Fs * stepMs/1000) - 1;
            iSteady0 = iSteady1 - round(tc.Fs * 0.030) + 1;
            steady   = mean(ai(iSteady0:iSteady1));

            expectedDvMv = stepPa * be.RinputMOhm / 1000;  % mV
            tc.verifyEqual(steady - baseline, expectedDvMv, "RelTol", 0.10);
        end

        function testRngSeedDeterministic(tc)
            tele = patchclamp.hardware.FakeTelegraph();
            N = round(tc.Fs * tc.DurationSec);
            ao0 = tc.flatZeroCommand(tc.Fs, tc.DurationSec);
            led = tc.zeroLed(tc.Fs, tc.DurationSec);

            be1 = patchclamp.hardware.FakeBackend(tele, rngSeed = 42);
            be1.configureTrial(ao0, led, "ai1", tc.Fs, tc.DurationSec);
            r1 = be1.run();

            be2 = patchclamp.hardware.FakeBackend(tele, rngSeed = 42);
            be2.configureTrial(ao0, led, "ai1", tc.Fs, tc.DurationSec);
            r2 = be2.run();

            tc.verifyEqual(r1, r2);
        end

        function testModeSwitchChangesUnits(tc)
            tele = patchclamp.hardware.FakeTelegraph();   % VC
            be   = patchclamp.hardware.FakeBackend(tele, rngSeed = 5);
            ao0 = tc.flatZeroCommand(tc.Fs, tc.DurationSec);
            led = tc.zeroLed(tc.Fs, tc.DurationSec);

            be.configureTrial(ao0, led, "ai1", tc.Fs, tc.DurationSec);
            aiVc = be.run();
            % VC flat zero -> baseline current ~ (Vhold - Vrest)/Rinput * 1000
            % = (-70 - -65)/150 * 1000 = -33.3 pA. Sign: negative. Magnitude:
            % tens of pA. Definitely not in mV range.
            tc.verifyLessThan(mean(aiVc), 0);
            tc.verifyGreaterThan(mean(aiVc), -100);

            tele.setMode("IC");
            be.configureTrial(ao0, led, "ai1", tc.Fs, tc.DurationSec);
            aiIc = be.run();
            % IC flat zero -> baseline ~ Vrest = -65 mV. Negative, in tens of mV.
            tc.verifyLessThan(mean(aiIc), -50);
            tc.verifyGreaterThan(mean(aiIc), -80);
        end

        function testCleanupResetsState(tc)
            tele = patchclamp.hardware.FakeTelegraph();
            be   = patchclamp.hardware.FakeBackend(tele);
            ao0 = tc.flatZeroCommand(tc.Fs, tc.DurationSec);
            led = tc.zeroLed(tc.Fs, tc.DurationSec);
            be.configureTrial(ao0, led, "ai1", tc.Fs, tc.DurationSec);
            be.cleanup();
            tc.verifyError(@() be.run(), ...
                "patchclamp:hardware:FakeBackend:notConfigured");
            % Idempotent: a second cleanup is a no-op.
            be.cleanup();
        end
    end
end
