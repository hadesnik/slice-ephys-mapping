classdef test_sweep_runner_mock < matlab.unittest.TestCase
    %test_sweep_runner_mock The free-running sweep loop against the mock rig.
    %
    %   The behaviours pinned here are the ones the experimenter depends on
    %   while patching: sweeps keep coming, Stop and Pause actually work, a
    %   parameter edited mid-run applies to the NEXT sweep and not the one in
    %   flight, stepped families advance the parameter they say they advance,
    %   and the seal readout matches the cell it is measuring.
    %
    %   Timing-sensitive tests use generous bounds: the mock's clock is wall
    %   time, so exact sweep counts would be flaky.

    properties
        TmpDir
        SweepEvents = 0
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TmpDir = tempname();
            mkdir(tc.TmpDir);
            tc.SweepEvents = 0;
        end
    end

    methods (TestMethodTeardown)
        function teardown(tc)
            if isfolder(tc.TmpDir)
                rmdir(tc.TmpDir, 's');
            end
        end
    end

    methods (Test)

        function one_sweep_recovers_ground_truth(tc)
            [runner, model] = tc.buildRunner('VC');
            % acquireOne, not start/stop: start() free-runs, and a sweep longer
            % than the ISI legitimately fires the next one before Stop lands.
            runner.acquireOne();

            tc.verifyEqual(runner.sweepCount, 1);
            tc.verifyEqual(runner.state, 'Idle');
            s = runner.lastSweep;
            tc.assertNotEmpty(s);
            tc.verifyEqual(s.seal.rsMohm, model.params.rsMohm, 'RelTol', 0.15);
            tc.verifyEqual(s.seal.riMohm, model.params.rinMohm, 'RelTol', 0.15);
            tc.verifyNumElements(runner.rsMohm, 1);
        end

        function free_running_keeps_producing_sweeps(tc)
            [runner, ~] = tc.buildRunner('VC');
            runner.config.isiS = 0.05;
            lh = event.listener(runner, 'SweepFinished', @(~, ~) tc.bump()); %<NASGU>

            runner.start();
            waitUntil(@() runner.sweepCount >= 3, 10);
            runner.stop();

            tc.verifyGreaterThanOrEqual(runner.sweepCount, 3);
            tc.verifyEqual(tc.SweepEvents, runner.sweepCount);
            tc.verifyNumElements(runner.rsMohm, runner.sweepCount);
            tc.verifyEqual(runner.state, 'Idle');
        end

        function stop_halts_the_loop(tc)
            [runner, ~] = tc.buildRunner('VC');
            runner.config.isiS = 0.05;
            runner.start();
            waitUntil(@() runner.sweepCount >= 2, 10);
            runner.stop();

            n = runner.sweepCount;
            pause(0.5);
            tc.verifyEqual(runner.sweepCount, n, 'sweeps continued after stop()');
        end

        function pause_holds_and_resume_continues_the_count(tc)
            [runner, ~] = tc.buildRunner('VC');
            runner.config.isiS = 0.05;
            runner.start();
            waitUntil(@() runner.sweepCount >= 2, 10);
            runner.pause();

            tc.verifyEqual(runner.state, 'Paused');
            n = runner.sweepCount;
            pause(0.4);
            tc.verifyEqual(runner.sweepCount, n, 'sweeps continued while paused');

            runner.resume();
            waitUntil(@() runner.sweepCount > n, 10);
            runner.stop();
            tc.verifyGreaterThan(runner.sweepCount, n);
            % The history is continuous across the pause, not restarted.
            tc.verifyNumElements(runner.rsMohm, runner.sweepCount);
        end

        function parameter_edit_applies_to_the_next_sweep(tc)
            % The behaviour the whole live-editing design exists for.
            % The command train starts after the test pulse ends (70-170 ms):
            % the two trains SUM on the command line, as they did in the legacy
            % AO0 = testpulse + CCoutput1, so an overlap would read as amp-20.
            [runner, ~] = tc.buildRunner('IC');
            runner.config.command = struct('startTimeMs', 300, 'nPulses', 1, ...
                'pulseDurationMs', 50, 'amplitude', 100, 'frequencyHz', 10);

            runner.acquireOne();
            first = max(runner.lastSweep.cellCmd);
            tc.verifyEqual(first, 100, 'AbsTol', 1e-9);

            runner.config.command.amplitude = 250;
            runner.acquireOne();
            second = max(runner.lastSweep.cellCmd);
            tc.verifyEqual(second, 250, 'AbsTol', 1e-9);
        end

        function stepping_advances_the_named_parameter(tc)
            % One mechanism serves the F/I family and the LED parameter sweep.
            [runner, ~] = tc.buildRunner('IC');
            runner.config.command = struct('startTimeMs', 300, 'nPulses', 1, ...
                'pulseDurationMs', 50, 'amplitude', 0, 'frequencyHz', 10);
            runner.stepSpec = struct('channel', 'command', ...
                'parameter', 'amplitude', 'delta', 20);

            amps = zeros(1, 3);
            for k = 1:3
                runner.acquireOne();
                amps(k) = max(runner.lastSweep.cellCmd);
            end
            % First sweep delivers 0, then 20, then 40.
            tc.verifyEqual(amps, [0 20 40], 'AbsTol', 1e-9);
            % And the config reflects what will be delivered next.
            tc.verifyEqual(runner.config.command.amplitude, 60, 'AbsTol', 1e-9);
        end

        function stepping_can_target_the_led_channel(tc)
            [runner, ~] = tc.buildRunner('VC');
            runner.config.led = struct('startTimeMs', 100, 'nPulses', 2, ...
                'pulseDurationMs', 10, 'amplitude', 1, 'frequencyHz', 10);
            runner.stepSpec = struct('channel', 'led', ...
                'parameter', 'frequencyHz', 'delta', 5);

            runner.acquireOne();
            tc.verifyEqual(runner.config.led.frequencyHz, 15, 'AbsTol', 1e-9);
            % The command channel is untouched.
            tc.verifyFalse(isfield(runner.config, 'commandStepped'));
        end

        function seal_test_mode_strips_the_stimulus(tc)
            [runner, model] = tc.buildRunner('VC');
            runner.config.command = struct('startTimeMs', 100, 'nPulses', 1, ...
                'pulseDurationMs', 50, 'amplitude', 500, 'frequencyHz', 10);
            runner.config.led = struct('startTimeMs', 100, 'nPulses', 1, ...
                'pulseDurationMs', 10, 'amplitude', 2, 'frequencyHz', 10);
            runner.config.sealTestMode = true;

            runner.acquireOne();
            s = runner.lastSweep;

            tc.verifyEqual(nnz(s.led), 0, 'the laser must be dark in seal-test mode');
            tc.verifyEqual(max(s.cellCmd), 0, 'AbsTol', 1e-9, ...
                'the command train must not be delivered in seal-test mode');
            % Still measures the cell.
            tc.verifyEqual(s.seal.rsMohm, model.params.rsMohm, 'RelTol', 0.15);
        end

        function preview_matches_what_the_sweep_delivers(tc)
            % The stimulus panels draw previewSweep(); it must not drift.
            [runner, ~] = tc.buildRunner('IC');
            runner.config.command = struct('startTimeMs', 200, 'nPulses', 2, ...
                'pulseDurationMs', 20, 'amplitude', 75, 'frequencyHz', 10);

            [pCmd, pLed] = runner.previewSweep();
            runner.acquireOne();

            tc.verifyEqual(runner.lastSweep.cellCmd, pCmd, 'AbsTol', 1e-12);
            tc.verifyEqual(runner.lastSweep.led, pLed, 'AbsTol', 1e-12);
        end

        function save_hook_receives_every_sweep(tc)
            [runner, ~] = tc.buildRunner('VC');
            saved = {};
            runner.saveFcn = @(s) assignSaved(s);
            runner.acquireOne();
            runner.acquireOne();
            tc.verifyNumElements(saved, 2);
            tc.verifyEqual(saved{2}.index, 2);

            function assignSaved(s)
                saved{end+1} = s; %#ok<AGROW>
            end
        end

        function reset_clears_history_but_only_when_idle(tc)
            [runner, ~] = tc.buildRunner('VC');
            runner.acquireOne();
            tc.verifyEqual(runner.sweepCount, 1);
            runner.reset();
            tc.verifyEqual(runner.sweepCount, 0);
            tc.verifyEmpty(runner.rsMohm);
        end

        function daq_failure_surfaces_and_stops(tc)
            [runner, ~] = tc.buildRunner('VC');
            runner.config.durationS = -1;   % makes sweepWaveform reject it
            fired = false;
            lh = event.listener(runner, 'AcquisitionError', @(~, ~) setFired()); %<NASGU>

            runner.start();

            tc.verifyTrue(fired);
            tc.verifyEqual(runner.state, 'Idle');
            tc.verifyNotEmpty(runner.lastError);

            function setFired()
                fired = true;
            end
        end
    end

    methods (Access = private)
        function bump(tc)
            tc.SweepEvents = tc.SweepEvents + 1;
        end

        function [runner, model] = buildRunner(tc, mode)
            cfg = semConfig();
            targets = struct('patchedCellId', 1, 'cells', struct( ...
                'id', 1, 'scanfieldXY', [0, 0], 'dmdXY', [100, 100], 'layer', 1, ...
                'isOpsinPos', true, 'score', 1, 'notes', ''));
            model = sem.sim.makeGroundTruthNetwork(cfg, targets);

            daq = sem.hardware.MockEphysDAQ();
            daq.initialize(cfg.daq);
            daq.attachNetworkModel(model);
            sem.hardware.notifyClampState(daq, struct('mode', mode, 'holdingMv', 0));
            tc.addTeardown(@() daq.cleanup());

            telegraph = sem.hardware.ConfigTelegraph(cfg, mode);
            adapter = sem.hardware.PatchDaqAdapter(daq, cfg, telegraph);

            sweepCfg = sweepDefaults(cfg);
            runner = sem.acq.SweepRunner(adapter, telegraph, sweepCfg, tc.TmpDir);
            tc.addTeardown(@() delete(runner));
        end
    end
end

% --- local helpers ---------------------------------------------------------

function waitUntil(predicate, timeoutS)
t0 = tic;
while ~predicate() && toc(t0) < timeoutS
    pause(0.02);
end
end

function cfg = semConfig()
cfg = struct();
d = struct();
d.sampleRate = 20000;
d.analogInChannels = [0, 1];
d.aiRangeV = [-10, 10];
d.analogOutChannels = [0, 1];
d.digitalInChannels = {};
d.digitalOutChannels = {'port0/line0'};
d.ai_scaledOutput = 0;
d.ao_laser = 0;
d.ao_cellCommand = 1;
cfg.daq = d;
cfg.ephys = struct( ...
    'commandVcMvPerV', 20, 'commandIcPaPerV', 400, ...
    'scaledVcPaPerV', 1000, 'scaledIcMvPerMv', 20, ...
    'sealTest_preMs', 20, 'sealTest_stepMs', 100, 'sealTest_postMs', 30, ...
    'sealTest_amplitudeVcMv', -5, 'sealTest_amplitudeIcPa', -20);
cfg.groundTruth = struct('nCells', 1, 'seed', 3, ...
    'rsMohm', 15, 'rinMohm', 150, 'cmPf', 100, 'vrestMv', -65, ...
    'noiseRmsPa', 0.5, 'noiseRmsMv', 0.05);
cfg.fov = struct();
end

function s = sweepDefaults(cfg)
s = cfg.ephys;              % carries the flat sealTest_* keys
s.sampleRateHz = cfg.daq.sampleRate;
s.durationS = 0.5;
s.isiS = 0.05;
s.testPulse = true;
s.testPulseStartMs = 50;
s.sealTestIsiS = 0.1;
s.sealTestDurationS = 0.2;
s.command = struct();
s.led = struct();
end
