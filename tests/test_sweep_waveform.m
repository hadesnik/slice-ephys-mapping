classdef test_sweep_waveform < matlab.unittest.TestCase
    %test_sweep_waveform The acquisition GUI's stimulus grammar.
    %
    %   sem.protocol.pulseTrain is the primitive behind both stimulus panels,
    %   and sem.protocol.sweepWaveform composes one sweep from it. The
    %   parameters here are the ones printed on the GUI, so the tests are
    %   written in those terms: a pulse starting at N ms, this wide, this many,
    %   at this rate.
    %
    %   The last test closes the loop that matters clinically: a composed sweep
    %   driven through the mock cell must give back the ground-truth Rs and Rin,
    %   which is what the live readout claims to show.

    methods (Test)

        % --- the primitive --------------------------------------------------

        function places_pulses_at_sample_exact_positions(tc)
            fs = 20000;
            spec = struct('startTimeMs', 100, 'nPulses', 3, ...
                'pulseDurationMs', 10, 'amplitude', 5, 'frequencyHz', 20);
            [w, info] = sem.protocol.pulseTrain(spec, fs, 1.0);

            tc.verifySize(w, [20000, 1]);
            % 100 ms -> sample 2001; 10 ms wide -> 200 samples; 20 Hz -> 1000 apart.
            tc.verifyEqual(info.onsetIdx, [2001, 3001, 4001]);
            tc.verifyEqual(info.periodSamples, 1000);
            tc.verifyEqual(w(2001), 5);
            tc.verifyEqual(w(2200), 5);
            tc.verifyEqual(w(2201), 0);
            tc.verifyEqual(nnz(w == 5), 3 * 200);
        end

        function frequency_is_onset_to_onset_not_a_gap(tc)
            % 10 Hz with 50 ms pulses => onsets 100 ms apart, 50 ms gaps.
            fs = 10000;
            spec = struct('startTimeMs', 0, 'nPulses', 2, ...
                'pulseDurationMs', 50, 'amplitude', 1, 'frequencyHz', 10);
            [~, info] = sem.protocol.pulseTrain(spec, fs, 1.0);
            tc.verifyEqual(diff(info.onsetIdx), fs / 10);
        end

        function zero_start_time_lands_on_the_first_sample(tc)
            % The legacy version indexed from 0 here and errored.
            spec = struct('startTimeMs', 0, 'nPulses', 1, ...
                'pulseDurationMs', 1, 'amplitude', 3, 'frequencyHz', 1);
            [w, info] = sem.protocol.pulseTrain(spec, 20000, 0.5);
            tc.verifyEqual(info.onsetIdx, 1);
            tc.verifyEqual(w(1), 3);
        end

        function tail_is_forced_to_zero(tc)
            % A light source must not be left on between sweeps.
            spec = struct('startTimeMs', 0, 'nPulses', 1, ...
                'pulseDurationMs', 1000, 'amplitude', 4, 'frequencyHz', 1);
            w = sem.protocol.pulseTrain(spec, 20000, 0.5);
            tc.verifyEqual(w(end - 9:end), zeros(10, 1));
        end

        function empty_train_is_not_an_error(tc)
            % The Clear state: no pulses, or zero amplitude.
            base = struct('startTimeMs', 10, 'pulseDurationMs', 5, ...
                'amplitude', 1, 'frequencyHz', 10);
            noPulses = base; noPulses.nPulses = 0;
            noAmp = base; noAmp.nPulses = 5; noAmp.amplitude = 0;

            tc.verifyEqual(nnz(sem.protocol.pulseTrain(noPulses, 20000, 0.5)), 0);
            tc.verifyEqual(nnz(sem.protocol.pulseTrain(noAmp, 20000, 0.5)), 0);
        end

        function overrunning_train_truncates_rather_than_errors(tc)
            % Turning the pulse count up mid-experiment must not kill the loop.
            spec = struct('startTimeMs', 0, 'nPulses', 100, ...
                'pulseDurationMs', 10, 'amplitude', 1, 'frequencyHz', 10);
            [w, info] = sem.protocol.pulseTrain(spec, 20000, 0.5);
            tc.verifyTrue(info.truncated);
            tc.verifyLessThan(numel(info.onsetIdx), 100);
            tc.verifySize(w, [10000, 1]);
        end

        function bad_inputs_error_with_sem_ids(tc)
            good = struct('startTimeMs', 0, 'nPulses', 1, ...
                'pulseDurationMs', 5, 'amplitude', 1, 'frequencyHz', 10);
            tc.verifyError(@() sem.protocol.pulseTrain(good, -1, 0.5), ...
                'sem:protocol:pulseTrain:badRate');
            tc.verifyError(@() sem.protocol.pulseTrain(good, 20000, 0), ...
                'sem:protocol:pulseTrain:badDuration');
            bad = good; bad.frequencyHz = 0;
            tc.verifyError(@() sem.protocol.pulseTrain(bad, 20000, 0.5), ...
                'sem:protocol:pulseTrain:badFrequency');
        end

        % --- the sweep ------------------------------------------------------

        function sweep_sums_test_pulse_and_command_train(tc)
            fs = 20000;
            cfg = tc.sweepCfg();
            cfg.command = struct('startTimeMs', 500, 'nPulses', 1, ...
                'pulseDurationMs', 100, 'amplitude', 200, 'frequencyHz', 10);
            [cmd, led, layout] = sem.protocol.sweepWaveform(cfg, 'IC', fs);

            tc.verifySize(cmd, [fs, 1]);
            tc.verifyEqual(nnz(led), 0, 'no LED train was configured');
            % Test pulse present at its own place...
            tc.verifyFalse(isnan(layout.sealTestStepStartIdx));
            tc.verifyLessThan(cmd(layout.sealTestStepStartIdx + 10), 0);
            % ...and the command train at 500 ms is independent of it.
            tc.verifyEqual(layout.commandOnsetIdx, 10001);
            tc.verifyEqual(cmd(10500), 200);
        end

        function led_train_is_independent_of_the_command(tc)
            fs = 20000;
            cfg = tc.sweepCfg();
            cfg.led = struct('startTimeMs', 750, 'nPulses', 3, ...
                'pulseDurationMs', 10, 'amplitude', 0.4, 'frequencyHz', 10);
            [~, led, layout] = sem.protocol.sweepWaveform(cfg, 'VC', fs);

            tc.verifyEqual(layout.ledOnsetIdx, [15001, 17001, 19001]);
            tc.verifyEqual(led(15001), 0.4);
        end

        function test_pulse_can_be_switched_off(tc)
            cfg = tc.sweepCfg();
            cfg.testPulse = false;
            [cmd, ~, layout] = sem.protocol.sweepWaveform(cfg, 'VC', 20000);
            tc.verifyEqual(nnz(cmd), 0);
            tc.verifyTrue(isnan(layout.sealTestStartIdx));
        end

        function mode_selects_the_test_pulse_amplitude(tc)
            cfg = tc.sweepCfg();
            vc = sem.protocol.sweepWaveform(cfg, 'VC', 20000);
            ic = sem.protocol.sweepWaveform(cfg, 'IC', 20000);
            % configured as -5 mV in VC and -20 pA in IC
            tc.verifyEqual(min(vc), -5);
            tc.verifyEqual(min(ic), -20);
        end

        function bad_mode_errors(tc)
            tc.verifyError(@() sem.protocol.sweepWaveform(tc.sweepCfg(), 'XX', 20000), ...
                'sem:protocol:sweepWaveform:badMode');
        end

        % --- the loop that matters -----------------------------------------

        function composed_sweep_recovers_ground_truth_rs_and_rin(tc)
            % Drive the mock cell with a real composed sweep and check that the
            % seal analysis gives back what the model was built with. This is
            % the number the live GUI readout will show.
            fs = 20000;
            model = makeModel();
            cfg = tc.sweepCfg();
            cfg.durationS = 0.5;

            [cmdCell, ~, layout] = sem.protocol.sweepWaveform(cfg, 'VC', fs);
            holdingMv = -70;
            ai = model.synthesizePassive(holdingMv + cmdCell, 'VC', fs);
            ai = ai + 0.5 * randn(numel(ai), 1);

            res = sem.analysis.sealAnalysis(ai, 'VC', cfg, fs, layout);
            tc.verifyEqual(res.rsMohm, model.params.rsMohm, 'RelTol', 0.10);
            tc.verifyEqual(res.riMohm, model.params.rinMohm, 'RelTol', 0.10);
        end
    end

    methods (Access = private)
        function cfg = sweepCfg(~)
            cfg = struct();
            cfg.durationS = 1.0;
            cfg.testPulse = true;
            cfg.testPulseStartMs = 50;
            cfg.sealTest_preMs = 20;
            cfg.sealTest_stepMs = 100;
            cfg.sealTest_postMs = 30;
            cfg.sealTest_amplitudeVcMv = -5;
            cfg.sealTest_amplitudeIcPa = -20;
        end
    end
end

% --- local helpers ---------------------------------------------------------

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
