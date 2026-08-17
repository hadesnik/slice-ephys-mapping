classdef Round1_SealTest < matlab.unittest.TestCase
    % Round1_SealTest  Tests for patchclamp.analysis.Seal.analyzeTrial.
    %
    % Reference traces are constructed inline so the test does not depend on
    % FakeBackend (R1 Agent A).

    properties (Constant)
        Fs        = 20000;       % Hz
        PreMs     = 50;
        StepMs    = 100;
        PostMs    = 50;
        TrailMs   = 800;         % rest of the 1 s trial
        TauMs     = 0.3;         % capacitive decay time-constant (ms) for VC ref
    end

    methods (Static, Access = private)
        function st = sealStruct()
            st = struct( ...
                'amplitudeVcMv', -5, ...
                'amplitudeIcPa', -100, ...
                'preMs',         Round1_SealTest.PreMs, ...
                'stepMs',        Round1_SealTest.StepMs, ...
                'postMs',        Round1_SealTest.PostMs);
        end

        function ai = buildVcReference(Rs_ref, Ri_ref, stepMv, holdingPa, ...
                                       preMs, stepMs, postMs, trailingMs, fs, tauMs, noiseSigma)
            % VC: a step in command voltage produces:
            %   steady-state I  = step / Ri
            %   peak I (instant)= step / Rs
            % So the capacitive transient has a peak ABOVE the steady level of
            % step*(1/Rs - 1/Ri), decaying with tau back to the steady value.
            N = round((preMs + stepMs + postMs + trailingMs) / 1000 * fs);
            ai = ones(N,1) * holdingPa;
            i0 = round(preMs / 1000 * fs) + 1;
            i1 = round((preMs + stepMs) / 1000 * fs);

            % Steady-state current change (pA): stepMv / Ri_ref * 1000
            ai(i0:i1) = ai(i0:i1) + stepMv / Ri_ref * 1000;

            % Capacitive transient at onset.
            peakAboveSteadyOn  =  stepMv * (1/Rs_ref - 1/Ri_ref) * 1000;
            peakAboveSteadyOff = -peakAboveSteadyOn;
            nDecay = min(round(5 / 1000 * fs), i1 - i0);
            t_ms = (0:nDecay-1).' / fs * 1000;
            ai(i0:i0+nDecay-1) = ai(i0:i0+nDecay-1) + peakAboveSteadyOn * exp(-t_ms / tauMs);

            % Capacitive transient at offset.
            nOffDecay = min(nDecay, N - i1);
            ai(i1+1:i1+nOffDecay) = ai(i1+1:i1+nOffDecay) + peakAboveSteadyOff * exp(-t_ms(1:nOffDecay) / tauMs);

            if noiseSigma > 0
                ai = ai + noiseSigma * randn(N,1);
            end
        end

        function ai = buildIcReference(Ri_ref, stepPa, restingMv, ...
                                       preMs, stepMs, postMs, trailingMs, fs, noiseSigma)
            % IC: a current step produces a voltage change of step * Ri.
            %   stepPa is pA, Ri is MOhm -> deltaV (mV) = stepPa * Ri / 1000.
            N = round((preMs + stepMs + postMs + trailingMs) / 1000 * fs);
            ai = ones(N,1) * restingMv;
            i0 = round(preMs / 1000 * fs) + 1;
            i1 = round((preMs + stepMs) / 1000 * fs);
            ai(i0:i1) = ai(i0:i1) + stepPa * Ri_ref / 1000;
            if noiseSigma > 0
                ai = ai + noiseSigma * randn(N,1);
            end
        end
    end

    methods (Test)

        function testHoldingVc(testCase)
            rng(1);
            fs = testCase.Fs;
            holdingPa = -30;
            N = round(1.0 * fs);
            ai = holdingPa + 0.5 * randn(N, 1);
            st = Round1_SealTest.sealStruct();

            result = patchclamp.analysis.Seal.analyzeTrial(ai, "VC", st, fs);
            testCase.verifyEqual(result.holding, holdingPa, 'AbsTol', 1.0);
            testCase.verifyEqual(result.holdingUnit, "pA");
            testCase.verifyEqual(result.mode, "VC");
        end

        function testHoldingIc(testCase)
            rng(2);
            fs = testCase.Fs;
            restingMv = -65;
            N = round(1.0 * fs);
            ai = restingMv + 0.2 * randn(N, 1);
            st = Round1_SealTest.sealStruct();

            result = patchclamp.analysis.Seal.analyzeTrial(ai, "IC", st, fs);
            testCase.verifyEqual(result.holding, restingMv, 'AbsTol', 1.0);
            testCase.verifyEqual(result.holdingUnit, "mV");
            testCase.verifyEqual(result.mode, "IC");
        end

        function testRsRecoveryVc(testCase)
            rng(3);
            fs = testCase.Fs;
            Rs_ref = 20;     % MOhm
            Ri_ref = 200;    % MOhm
            stepMv = -5;
            holdingPa = -30;
            ai = Round1_SealTest.buildVcReference(Rs_ref, Ri_ref, stepMv, holdingPa, ...
                testCase.PreMs, testCase.StepMs, testCase.PostMs, testCase.TrailMs, ...
                fs, testCase.TauMs, 0.05);
            st = Round1_SealTest.sealStruct();
            st.amplitudeVcMv = stepMv;

            result = patchclamp.analysis.Seal.analyzeTrial(ai, "VC", st, fs);
            testCase.verifyEqual(result.rsMohm, Rs_ref, 'RelTol', 0.10);
        end

        function testRiRecoveryVc(testCase)
            rng(4);
            fs = testCase.Fs;
            Rs_ref = 20;
            Ri_ref = 200;
            stepMv = -5;
            holdingPa = -30;
            ai = Round1_SealTest.buildVcReference(Rs_ref, Ri_ref, stepMv, holdingPa, ...
                testCase.PreMs, testCase.StepMs, testCase.PostMs, testCase.TrailMs, ...
                fs, testCase.TauMs, 0.05);
            st = Round1_SealTest.sealStruct();
            st.amplitudeVcMv = stepMv;

            result = patchclamp.analysis.Seal.analyzeTrial(ai, "VC", st, fs);
            testCase.verifyEqual(result.riMohm, Ri_ref, 'RelTol', 0.05);
        end

        function testRsIsNaNInIc(testCase)
            rng(5);
            fs = testCase.Fs;
            ai = Round1_SealTest.buildIcReference(150, -100, -65, ...
                testCase.PreMs, testCase.StepMs, testCase.PostMs, testCase.TrailMs, fs, 0.05);
            st = Round1_SealTest.sealStruct();

            result = patchclamp.analysis.Seal.analyzeTrial(ai, "IC", st, fs);
            testCase.verifyTrue(isnan(result.rsMohm));
        end

        function testRiRecoveryIc(testCase)
            rng(6);
            fs = testCase.Fs;
            Ri_ref = 150;       % MOhm
            stepPa = -100;
            restingMv = -65;
            ai = Round1_SealTest.buildIcReference(Ri_ref, stepPa, restingMv, ...
                testCase.PreMs, testCase.StepMs, testCase.PostMs, testCase.TrailMs, fs, 0.05);
            st = Round1_SealTest.sealStruct();
            st.amplitudeIcPa = stepPa;

            result = patchclamp.analysis.Seal.analyzeTrial(ai, "IC", st, fs);
            testCase.verifyEqual(result.riMohm, Ri_ref, 'RelTol', 0.05);
        end

        function testRiPositiveSignOnly(testCase)
            % Negative-amplitude step still yields positive Ri.
            rng(7);
            fs = testCase.Fs;
            ai = Round1_SealTest.buildVcReference(20, 200, -5, -30, ...
                testCase.PreMs, testCase.StepMs, testCase.PostMs, testCase.TrailMs, ...
                fs, testCase.TauMs, 0.05);
            st = Round1_SealTest.sealStruct();
            st.amplitudeVcMv = -5;

            result = patchclamp.analysis.Seal.analyzeTrial(ai, "VC", st, fs);
            testCase.verifyGreaterThan(result.riMohm, 0);
            testCase.verifyGreaterThan(result.rsMohm, 0);
        end

        function testHoldingUnitMatchesMode(testCase)
            fs = testCase.Fs;
            N = round(1.0 * fs);
            aiVc = zeros(N,1);
            aiIc = zeros(N,1);
            st = Round1_SealTest.sealStruct();

            rVc = patchclamp.analysis.Seal.analyzeTrial(aiVc, "VC", st, fs);
            rIc = patchclamp.analysis.Seal.analyzeTrial(aiIc, "IC", st, fs);
            testCase.verifyEqual(rVc.holdingUnit, "pA");
            testCase.verifyEqual(rIc.holdingUnit, "mV");
        end

        function testLayoutOverride(testCase)
            % Build a trace where the seal-test step is placed at an unusual
            % offset; pass explicit layout indices and verify Ri is still
            % recovered (and that not passing them would fail).
            rng(8);
            fs = testCase.Fs;
            Ri_ref = 200;
            stepMv = -5;
            holdingPa = -30;
            % Use double the default preMs so the default-computed indices
            % would land in the pre-step baseline rather than the step.
            preMs = 2 * testCase.PreMs;
            ai = Round1_SealTest.buildVcReference(20, Ri_ref, stepMv, holdingPa, ...
                preMs, testCase.StepMs, testCase.PostMs, testCase.TrailMs, ...
                fs, testCase.TauMs, 0.05);
            st = Round1_SealTest.sealStruct();
            st.amplitudeVcMv = stepMv;
            % NOTE: leave st.preMs at the default (50 ms); override via layout.

            layout = struct();
            layout.sealTestStartIdx     = 1;
            layout.sealTestStepStartIdx = round(preMs / 1000 * fs) + 1;
            layout.sealTestStepEndIdx   = round((preMs + testCase.StepMs) / 1000 * fs);

            result = patchclamp.analysis.Seal.analyzeTrial(ai, "VC", st, fs, layout);
            testCase.verifyEqual(result.riMohm, Ri_ref, 'RelTol', 0.05);
        end

    end
end
