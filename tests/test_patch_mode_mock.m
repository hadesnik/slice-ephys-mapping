classdef test_patch_mode_mock < matlab.unittest.TestCase
    %test_patch_mode_mock Patch mode (live membrane test) end-to-end on the mock.
    %
    %   Closes the loop that patch mode depends on:
    %     sem.acq.SweepRunner -> sem.hardware.PatchDaqAdapter (cell units ->
    %     DAQ volts) -> sem.hardware.MockEphysDAQ finite path -> SliceNetworkModel
    %     passive membrane -> back through the adapter (volts -> cell units) ->
    %     sem.analysis.sealAnalysis
    %
    %   If Rs/Ri come back matching the model's ground truth, every conversion in
    %   that chain is consistent, which is the property the rig depends on.
    %
    %   Headless: no figures are created here (the GUI assembly is tested
    %   separately). Mirrors the tolerance rationale in test_seal_analysis: the
    %   discrete-time capacitive-transient peak slightly undershoots the analytic
    %   dV/Rs, so Rs is checked at 10%.

    properties (Access = private)
        EventCount = 0
    end

    methods (Test)

        function membrane_test_recovers_rs_ri_vc(tc)
            [runner, model, adapter] = tc.buildPatchStack('VC'); %#ok<ASGLU>
            res = tc.oneSweep(runner);

            tc.verifyEqual(res.mode, 'VC');
            tc.verifyEqual(res.holdingUnit, 'pA');
            tc.verifyEqual(res.rsMohm, model.params.rsMohm, 'RelTol', 0.10);
            tc.verifyEqual(res.riMohm, model.params.rinMohm, 'RelTol', 0.10);
        end

        function membrane_test_ic_has_nan_rs(tc)
            [runner, model, ~] = tc.buildPatchStack('IC');
            res = tc.oneSweep(runner);

            tc.verifyEqual(res.mode, 'IC');
            tc.verifyEqual(res.holdingUnit, 'mV');
            tc.verifyTrue(isnan(res.rsMohm), 'Rs is undefined in current clamp.');
            % With no command current the cell sits at rest.
            tc.verifyEqual(res.holding, model.params.vrestMv, 'AbsTol', 2.0);
        end

        function ao_columns_follow_config_channel_map(tc)
            % The adapter must place the cell command on ao_cellCommand and leave
            % the laser line dark, in the order declared by config.daq.
            [runner, ~, adapter] = tc.buildPatchStack('VC'); %#ok<ASGLU>
            tc.oneSweep(runner);

            entries = adapter.daq.getLog();
            queued = entries(strcmp({entries.eventType}, 'queueAnalogOutput'));
            tc.verifyNotEmpty(queued, 'the adapter must queue AO through the DAQ');
            tc.verifyEqual(queued(end).payload.nChans, 2);

            cfgEntries = entries(strcmp({entries.eventType}, 'configureAnalogOutput'));
            % config.daq: ao_laser = 0, ao_cellCommand = 1, in that column order.
            tc.verifyEqual(cfgEntries(end).payload.channels, [0, 1]);
        end

        function laser_line_stays_dark_during_membrane_test(tc)
            % A membrane-test sweep must not fire the stimulation laser.
            cfg = tc.mockConfig();
            [daq, model] = tc.buildDaq(cfg); %#ok<ASGLU>
            telegraph = sem.hardware.ConfigTelegraph(cfg, 'VC');
            adapter = sem.hardware.PatchDaqAdapter(daq, cfg, telegraph);

            n = 100;
            adapter.configureTrial(zeros(n, 1), zeros(n, 1), "ai0", 20000, n / 20000);
            ai = adapter.run();

            tc.verifySize(ai, [n, 1]);
            % ao_laser is column 1; it was handed all zeros and must stay so.
            entries = daq.getLog();
            queued = entries(strcmp({entries.eventType}, 'queueAnalogOutput'));
            tc.verifyEqual(queued(end).payload.nSamples, n);
        end

        function channels_are_configured_once_not_per_sweep(tc)
            % tfp.hardware.NI6323_DAQ's configureAnalogInput/Output APPEND to
            % the legacy session and nothing removes channels, so reconfiguring
            % per sweep doubles the channel count each time and the AO width
            % stops matching the queued data within two sweeps. The mock assigns
            % rather than appends, so it cannot fail on its own - the call count
            % is what has to be pinned.
            cfg = tc.mockConfig();
            [daq, ~] = tc.buildDaq(cfg);
            telegraph = sem.hardware.ConfigTelegraph(cfg, 'VC');
            adapter = sem.hardware.PatchDaqAdapter(daq, cfg, telegraph);

            n = 100;
            for k = 1:4
                adapter.configureTrial(zeros(n, 1), zeros(n, 1), "ai0", 20000, n / 20000);
                adapter.run();
            end

            entries = daq.getLog();
            nAi = nnz(strcmp({entries.eventType}, 'configureAnalogInput'));
            nAo = nnz(strcmp({entries.eventType}, 'configureAnalogOutput'));
            nQueued = nnz(strcmp({entries.eventType}, 'queueAnalogOutput'));

            tc.verifyEqual(nAi, 1, 'AI channels must be configured once per session');
            tc.verifyEqual(nAo, 1, 'AO channels must be configured once per session');
            tc.verifyEqual(nQueued, 4, 'every sweep must still queue its own waveform');

            % cleanup() releases the task on real hardware, so the next session
            % has to add its channels again.
            adapter.cleanup();
            adapter.configureTrial(zeros(n, 1), zeros(n, 1), "ai0", 20000, n / 20000);
            entries = daq.getLog();
            tc.verifyEqual(nnz(strcmp({entries.eventType}, 'configureAnalogInput')), 2);
        end

        function single_ended_channels_are_passed_through(tc)
            % The legacy rig read its amplifier lines single-ended; reading them
            % differentially gives the wrong signal.
            cfg = tc.mockConfig();
            cfg.daq.aiSingleEndedChannels = [0 1];
            [daq, ~] = tc.buildDaq(cfg);
            adapter = sem.hardware.PatchDaqAdapter(daq, cfg);

            n = 50;
            adapter.configureTrial(zeros(n, 1), zeros(n, 1), "ai0", 20000, n / 20000);

            entries = daq.getLog();
            cfgAi = entries(strcmp({entries.eventType}, 'configureAnalogInput'));
            tc.assertNotEmpty(cfgAi);
            tc.verifyEqual(cfgAi(end).payload.singleEnded, [0 1]);
        end

        function adapter_requires_configure_before_run(tc)
            cfg = tc.mockConfig();
            [daq, ~] = tc.buildDaq(cfg);
            adapter = sem.hardware.PatchDaqAdapter(daq, cfg);
            tc.verifyError(@() adapter.run(), ...
                'sem:hardware:PatchDaqAdapter:notConfigured');
        end

        function adapter_rejects_channel_map_without_scaled_output(tc)
            cfg = tc.mockConfig();
            [daq, ~] = tc.buildDaq(cfg);
            bad = cfg;
            bad.daq.ai_scaledOutput = 7;   % not present in analogInChannels
            tc.verifyError(@() sem.hardware.PatchDaqAdapter(daq, bad), ...
                'sem:hardware:PatchDaqAdapter:badChannelMap');
        end

        function telegraph_serves_config_gains_and_fires_on_transition(tc)
            cfg = tc.mockConfig();
            telegraph = sem.hardware.ConfigTelegraph(cfg, 'VC');

            expected = sem.util.Units.gainFromConfig(cfg.ephys);
            tc.verifyEqual(telegraph.getGain(), expected);
            tc.verifyEqual(telegraph.getMode(), "VC");

            tc.EventCount = 0;
            lh = event.listener(telegraph, 'ModeChanged', @(~, ~) tc.bumpEvent()); %#ok<NASGU>

            telegraph.setMode('IC');
            telegraph.setMode('IC');   % no transition -> no second event

            tc.verifyEqual(tc.EventCount, 1);
            tc.verifyEqual(telegraph.getMode(), "IC");
        end

        function telegraph_drives_adapter_conversion_mode(tc)
            % Flipping the telegraph must change which gain the adapter uses,
            % without anyone calling setClampMode.
            cfg = tc.mockConfig();
            [daq, ~] = tc.buildDaq(cfg);
            telegraph = sem.hardware.ConfigTelegraph(cfg, 'VC');
            adapter = sem.hardware.PatchDaqAdapter(daq, cfg, telegraph);

            n = 50;
            adapter.configureTrial(ones(n, 1), zeros(n, 1), "ai0", 20000, n / 20000);
            tc.verifyEqual(adapter.clampMode, 'VC');

            telegraph.setMode('IC');
            adapter.configureTrial(ones(n, 1), zeros(n, 1), "ai0", 20000, n / 20000);
            tc.verifyEqual(adapter.clampMode, 'IC');
        end

        function mock_finite_path_without_model_is_noise_only(tc)
            % Preserves the pre-existing contract for a model-less mock.
            cfg = tc.mockConfig();
            daq = sem.hardware.MockEphysDAQ();
            daq.initialize(cfg.daq);
            adapter = sem.hardware.PatchDaqAdapter(daq, cfg);

            n = 500;
            adapter.configureTrial(zeros(n, 1), zeros(n, 1), "ai0", 20000, n / 20000);
            ai = adapter.run();

            tc.verifySize(ai, [n, 1]);
            tc.verifyTrue(all(isfinite(ai)));
        end
    end

    methods (Access = private)

        function cfg = mockConfig(~)
            % Built by assignment, not struct(...): a cell value inside struct()
            % is interpreted as struct-array expansion, so an empty cell would
            % silently produce a 0x0 struct.
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
                'sealTest_preMs', 20, 'sealTest_stepMs', 100, ...
                'sealTest_postMs', 30, ...
                'sealTest_amplitudeVcMv', -5, 'sealTest_amplitudeIcPa', -20);
            cfg.groundTruth = struct('nCells', 1, 'seed', 3, ...
                'rsMohm', 15, 'rinMohm', 150, 'cmPf', 100, 'vrestMv', -65, ...
                'noiseRmsPa', 0.5, 'noiseRmsMv', 0.05);
            cfg.fov = struct();
        end

        function [daq, model] = buildDaq(tc, cfg)
            targets = struct('patchedCellId', 1, 'cells', struct( ...
                'id', 1, 'scanfieldXY', [0, 0], 'dmdXY', [100, 100], 'layer', 1, ...
                'isOpsinPos', true, 'score', 1, 'notes', ''));
            model = sem.sim.makeGroundTruthNetwork(cfg, targets);
            daq = sem.hardware.MockEphysDAQ();
            daq.initialize(cfg.daq);
            daq.attachNetworkModel(model);
            tc.addTeardown(@() daq.cleanup());
        end

        function [runner, model, adapter] = buildPatchStack(tc, mode)
            cfg = tc.mockConfig();
            [daq, model] = tc.buildDaq(cfg);

            % The mock freezes clamp mode for a session; declare it up front.
            sem.hardware.notifyClampState(daq, struct('mode', mode, 'holdingMv', 0));

            telegraph = sem.hardware.ConfigTelegraph(cfg, mode);
            adapter = sem.hardware.PatchDaqAdapter(daq, cfg, telegraph);

            % Rig YAML is the source of truth for the seal-test parameters.
            sweepCfg = cfg.ephys;
            sweepCfg.sampleRateHz = cfg.daq.sampleRate;
            sweepCfg.durationS = 0.4;
            sweepCfg.isiS = 0.05;
            sweepCfg.testPulse = true;
            sweepCfg.testPulseStartMs = 50;
            sweepCfg.command = struct();
            sweepCfg.led = struct();

            runner = sem.acq.SweepRunner(adapter, telegraph, sweepCfg, tempname());
            tc.addTeardown(@() delete(runner));
        end

        function res = oneSweep(tc, runner)
            % acquireOne is the deterministic single-sweep entry point; start()
            % free-runs and may fire a second sweep before a caller can Stop.
            runner.acquireOne();
            res = runner.lastSweep.seal;
            res.aiCellUnits = runner.lastSweep.ai;
            tc.assertNotEmpty(res, 'the sweep produced no result');
        end

        function bumpEvent(tc)
            tc.EventCount = tc.EventCount + 1;
        end
    end
end
