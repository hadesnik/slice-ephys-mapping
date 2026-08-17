classdef test_acq_window < matlab.unittest.TestCase
    %test_acq_window The acquisition window against the mock rig.
    %
    %   Headless: built with Visible='off'. uifigure and its widgets construct
    %   fine under `matlab -nodisplay` on this platform, so this runs in the
    %   normal suite.
    %
    %   What is pinned is the wiring and the contracts the experimenter relies
    %   on, not pixels: a sweep reaches the live axes and the trend readouts,
    %   the browser follows and navigates, the stimulus panels' parameters
    %   reach the composed waveform, an edit only takes effect when Update is
    %   pressed, the command units follow the clamp mode, and seal-test mode
    %   strips the stimulus while still measuring the cell.

    properties
        TmpDir
        Win
    end

    methods (TestMethodSetup)
        function setup(tc)
            tc.TmpDir = tempname();
            mkdir(tc.TmpDir);
        end
    end

    methods (TestMethodTeardown)
        function teardown(tc)
            if ~isempty(tc.Win) && isvalid(tc.Win)
                tc.Win.shutdown();
            end
            tc.Win = [];
            if isfolder(tc.TmpDir)
                rmdir(tc.TmpDir, 's');
            end
        end
    end

    methods (Test)

        function builds_with_a_simulated_cell(tc)
            tc.Win = tc.build();
            tc.verifyClass(tc.Win.Figure, 'matlab.ui.Figure');
            tc.verifyClass(tc.Win.Runner, 'sem.acq.SweepRunner');
            tc.verifyClass(tc.Win.Adapter, 'sem.hardware.PatchDaqAdapter');
            tc.verifyNotEmpty(tc.Win.Model, 'a mock rig must get simulated cells');
            tc.verifyNotEmpty(tc.Win.LedPanel);
            tc.verifyNotEmpty(tc.Win.CommandPanel);
        end

        function config_seeds_the_run_fields(tc)
            % The rig YAML is the source of truth; hard-coded widget defaults
            % must not silently override it.
            cfg = tc.mockConfig();
            cfg.sweep.durationS = 0.4;
            cfg.sweep.isiS = 1.25;
            tc.Win = tc.build(cfg);
            tc.verifyEqual(tc.Win.Runner.config.durationS, 0.4, 'AbsTol', 1e-9);
            tc.verifyEqual(tc.Win.Runner.config.isiS, 1.25, 'AbsTol', 1e-9);
        end

        function a_sweep_reaches_the_trace_and_the_readouts(tc)
            tc.Win = tc.build();
            tc.Win.Runner.acquireOne();

            s = tc.Win.Runner.lastSweep;
            tc.assertNotEmpty(s);
            tc.verifyTrue(isfinite(s.seal.rsMohm) && s.seal.rsMohm > 0);

            % Live trace drawn.
            liveLines = findall(tc.Win.Figure, 'Type', 'line');
            tc.verifyNotEmpty(liveLines);

            % The numeric readouts live in the strip titles — the improvement
            % over the legacy trends-only display.
            titles = tc.panelTitles();
            tc.verifyTrue(any(contains(titles, 'Rs =')), ...
                'the Rs strip must show a number');
            tc.verifyTrue(any(contains(titles, 'Rin =')));
            tc.verifyTrue(any(contains(titles, 'Holding =')));
            tc.verifyTrue(any(contains(titles, 'sweep 1')));
        end

        function browser_follows_the_newest_sweep_and_navigates(tc)
            tc.Win = tc.build();
            for k = 1:3
                tc.Win.Runner.acquireOne();
            end
            tc.verifyTrue(any(contains(tc.panelTitles(), 'Sweep browser — sweep 3')));

            tc.Win.browseStep(-1);
            tc.verifyTrue(any(contains(tc.panelTitles(), 'Sweep browser — sweep 2')));
            tc.Win.browseStep(+1);
            tc.verifyTrue(any(contains(tc.panelTitles(), 'Sweep browser — sweep 3')));

            % Past the ends it holds, rather than erroring (legacy behaviour).
            tc.Win.browseStep(+5);
            tc.verifyTrue(any(contains(tc.panelTitles(), 'Sweep browser — sweep 3')));
        end

        function panel_parameters_reach_the_composed_waveform(tc)
            tc.Win = tc.build();
            tc.Win.setClampMode('IC');   % so amplitude is pA and additive

            tc.Win.CommandPanel.setSpec(struct('startTimeMs', 300, ...
                'nPulses', 1, 'pulseDurationMs', 50, 'amplitude', 150, ...
                'frequencyHz', 1));
            tc.Win.CommandPanel.pressUpdate();

            [cmd, ~] = tc.Win.Runner.previewSweep();
            fs = tc.Win.Runner.config.sampleRateHz;
            % 300 ms in, clear of the test pulse, so it is the sweep maximum.
            tc.verifyEqual(max(cmd), 150, 'AbsTol', 1e-9);
            tc.verifyEqual(cmd(round(0.31 * fs)), 150, 'AbsTol', 1e-9);
        end

        function edit_takes_effect_only_when_update_is_pressed(tc)
            % The contract that lets a value be dialled in mid-run without the
            % half-typed number reaching the cell.
            tc.Win = tc.build();
            tc.Win.setClampMode('IC');
            tc.Win.CommandPanel.setSpec(struct('startTimeMs', 300, 'nPulses', 1, ...
                'pulseDurationMs', 50, 'amplitude', 100, 'frequencyHz', 1));
            tc.Win.CommandPanel.pressUpdate();
            tc.verifyEqual(tc.Win.Runner.config.command.amplitude, 100, 'AbsTol', 1e-9);

            % Type a new value but do not commit it.
            s = tc.Win.CommandPanel.spec();
            s.amplitude = 999;
            tc.Win.CommandPanel.setSpec(s);
            tc.verifyEqual(tc.Win.Runner.config.command.amplitude, 100, 'AbsTol', 1e-9, ...
                'an uncommitted edit must not reach the runner');

            tc.Win.CommandPanel.pressUpdate();
            tc.verifyEqual(tc.Win.Runner.config.command.amplitude, 999, 'AbsTol', 1e-9);
        end

        function led_panel_drives_the_light_channel(tc)
            tc.Win = tc.build();
            tc.Win.LedPanel.setSpec(struct('startTimeMs', 500, 'nPulses', 2, ...
                'pulseDurationMs', 5, 'amplitude', 3, 'frequencyHz', 20));
            tc.Win.LedPanel.pressUpdate();

            [~, led] = tc.Win.Runner.previewSweep();
            fs = tc.Win.Runner.config.sampleRateHz;
            tc.verifyEqual(max(led), 3, 'AbsTol', 1e-9);
            tc.verifyEqual(led(round(0.5 * fs) + 2), 3, 'AbsTol', 1e-9);
        end

        function command_units_follow_the_clamp_mode(tc)
            tc.Win = tc.build();
            tc.Win.setClampMode('VC');
            tc.verifyTrue(any(contains(tc.labelTexts(), 'pulse amplitude (mV)')));
            tc.Win.setClampMode('IC');
            tc.verifyTrue(any(contains(tc.labelTexts(), 'pulse amplitude (pA)')));
        end

        function stepping_from_the_panel_advances_the_family(tc)
            tc.Win = tc.build();
            tc.Win.setClampMode('IC');
            tc.Win.CommandPanel.setSpec(struct('startTimeMs', 300, 'nPulses', 1, ...
                'pulseDurationMs', 50, 'amplitude', 0, 'frequencyHz', 1));
            tc.Win.CommandPanel.setStepping('amplitude', 25, true);
            tc.Win.CommandPanel.pressUpdate();

            tc.Win.Runner.acquireOne();
            tc.Win.Runner.acquireOne();
            % Two sweeps delivered, so the next one carries 2 x 25.
            tc.verifyEqual(tc.Win.Runner.config.command.amplitude, 50, 'AbsTol', 1e-9);
        end

        function seal_mode_strips_the_stimulus_but_still_measures(tc)
            tc.Win = tc.build();
            tc.Win.LedPanel.setSpec(struct('startTimeMs', 100, 'nPulses', 1, ...
                'pulseDurationMs', 10, 'amplitude', 2, 'frequencyHz', 10));
            tc.Win.LedPanel.pressUpdate();

            tc.Win.setSealMode(true);
            tc.Win.Runner.acquireOne();
            s = tc.Win.Runner.lastSweep;

            tc.verifyEqual(nnz(s.led), 0, 'the laser must be dark while sealing');
            tc.verifyTrue(isfinite(s.seal.rsMohm) && s.seal.rsMohm > 0);
        end

        function sweeps_are_written_in_the_repo_trial_format(tc)
            tc.Win = tc.build();
            tc.Win.Runner.acquireOne();

            files = dir(fullfile(tc.Win.sweepDir(), 'trials', '*_meta.mat'));
            tc.assertNotEmpty(files, 'no sweep landed on disk');
            m = load(fullfile(files(1).folder, files(1).name));
            tc.verifyEqual(m.meta.metadata.ephys.kind, 'sweep');
            tc.verifyTrue(isfield(m.meta.metadata.ephys, 'gains'), ...
                'the gains snapshot is what makes the volts on disk readable');
            tc.verifyTrue(ischar(m.meta.metadata.ephys.clampMode), ...
                'no string type may reach a saved field Python reads');
        end

        function shutdown_is_idempotent(tc)
            tc.Win = tc.build();
            fig = tc.Win.Figure;
            tc.Win.shutdown();
            tc.Win.shutdown();
            tc.verifyFalse(isvalid(fig));
        end
    end

    methods (Access = private)
        function w = build(tc, cfg)
            if nargin < 2
                cfg = tc.mockConfig();
            end
            w = sem.gui.AcqWindow(cfg, 'Visible', "off", ...
                'SessionDir', fullfile(tc.TmpDir, 'sess'));
        end

        function cfg = mockConfig(tc)
            thisDir = fileparts(mfilename('fullpath'));
            cfg = tfp.io.loadConfig(fullfile(thisDir, '..', 'configs', 'mock.yaml'));
            cfg.paths.dataDir = tc.TmpDir;
            cfg.groundTruth.nCells = 6;
            cfg.groundTruth.opsinNegFraction = 0;
            cfg.sweep.durationS = 1.0;   % long enough for the stimuli placed below
            cfg.sweep.isiS = 0.05;
            cfg.ui.liveFigure = false;
        end

        function t = panelTitles(tc)
            p = findall(tc.Win.Figure, 'Type', 'uipanel');
            t = string({p.Title});
        end

        function t = labelTexts(tc)
            l = findall(tc.Win.Figure, 'Type', 'uilabel');
            t = string({l.Text});
        end
    end
end
