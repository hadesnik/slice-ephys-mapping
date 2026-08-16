classdef test_seal_analysis < matlab.unittest.TestCase
    %test_seal_analysis Seal-test analysis must recover the ground-truth
    %   Rs/Ri that SliceNetworkModel's passive arm synthesized (within 10% —
    %   the discrete-time capacitive-transient peak slightly undershoots the
    %   analytic dV/Rs). This closes the loop mock waveform -> mock membrane
    %   -> analyzer that the runner relies on for patch-quality monitoring.

    methods (Test)
        function recovers_rs_ri_vc(tc)
            fs = 20000;
            model = makeModel();
            sealCfg = struct('sealTest_preMs', 20, 'sealTest_stepMs', 100, ...
                'sealTest_postMs', 30, 'sealTest_amplitudeVcMv', -5);
            [sealCell, ~] = sem.protocol.sealTestWaveform(sealCfg, 'VC', fs);
            holdingMv = -70;
            cmd = holdingMv + sealCell;
            % Prepend a settled holding baseline so the transient rides on DC.
            settle = repmat(holdingMv, round(0.05 * fs), 1);
            ai = model.synthesizePassive([settle; cmd], 'VC', fs);
            ai = ai + 0.5 * randn(numel(ai), 1);   % light noise
            res = sem.analysis.sealAnalysis(ai, 'VC', sealCfg, fs, ...
                struct('sealTestStartIdx', numel(settle) + 1));
            tc.verifyEqual(res.rsMohm, model.params.rsMohm, 'RelTol', 0.10);
            tc.verifyEqual(res.riMohm, model.params.rinMohm, 'RelTol', 0.10);
            tc.verifyEqual(res.mode, 'VC');
        end

        function holding_reflects_dc(tc)
            fs = 20000;
            model = makeModel();
            sealCfg = struct('sealTest_preMs', 20, 'sealTest_stepMs', 100, ...
                'sealTest_postMs', 30, 'sealTest_amplitudeVcMv', -5);
            [sealCell, ~] = sem.protocol.sealTestWaveform(sealCfg, 'VC', fs);
            holdingMv = -70;
            settle = repmat(holdingMv, round(0.05 * fs), 1);
            ai = model.synthesizePassive([settle; holdingMv + sealCell], 'VC', fs);
            % A real trial snippet starts at SETTLED holding (the preceding
            % trials held the DC); trim the initial capacitive transient the
            % settle segment's own onset edge produces.
            trim = round(0.04 * fs);
            ai = ai(trim + 1:end);
            res = sem.analysis.sealAnalysis(ai, 'VC', sealCfg, fs, ...
                struct('sealTestStartIdx', numel(settle) + 1 - trim));
            % Expected holding current: (Vhold - Vrest)/Rin in pA.
            expectedPa = (holdingMv - model.params.vrestMv) / model.params.rinMohm * 1000;
            tc.verifyEqual(res.holding, expectedPa, 'RelTol', 0.05);
            tc.verifyEqual(res.holdingUnit, 'pA');
        end

        function ic_mode_has_nan_rs(tc)
            fs = 20000;
            sealCfg = struct('sealTest_preMs', 20, 'sealTest_stepMs', 100, ...
                'sealTest_postMs', 30, 'sealTest_amplitudeIcPa', -20);
            model = makeModel();
            [sealCell, ~] = sem.protocol.sealTestWaveform(sealCfg, 'IC', fs);
            ai = model.synthesizePassive(sealCell, 'IC', fs);
            res = sem.analysis.sealAnalysis(ai, 'IC', sealCfg, fs);
            tc.verifyTrue(isnan(res.rsMohm));
            tc.verifyEqual(res.mode, 'IC');
        end

        function waveform_layout(tc)
            fs = 20000;
            sealCfg = struct('sealTest_preMs', 20, 'sealTest_stepMs', 100, ...
                'sealTest_postMs', 30, 'sealTest_amplitudeVcMv', -5);
            [w, layout] = sem.protocol.sealTestWaveform(sealCfg, 'VC', fs);
            tc.verifyEqual(numel(w), layout.preSamples + layout.stepSamples + layout.postSamples);
            tc.verifyEqual(w(layout.stepStartIdx), -5);
            tc.verifyEqual(w(layout.stepEndIdx), -5);
            tc.verifyEqual(w(1), 0);
            tc.verifyEqual(w(end), 0);
        end
    end
end

% --- Local helpers ---

function model = makeModel()
targets = struct('patchedCellId', 1, 'cells', struct( ...
    'id', 1, 'scanfieldXY', [0, 0], 'dmdXY', [100, 100], 'layer', 1, ...
    'isOpsinPos', true, 'score', 1, 'notes', ''));
config = struct('groundTruth', struct('nCells', 1, 'seed', 3, ...
    'rsMohm', 15, 'rinMohm', 150, 'cmPf', 100, 'vrestMv', -65, ...
    'noiseRmsPa', 0, 'noiseRmsMv', 0), ...
    'ephys', struct(), 'fov', struct());
model = sem.sim.makeGroundTruthNetwork(config, targets);
end
