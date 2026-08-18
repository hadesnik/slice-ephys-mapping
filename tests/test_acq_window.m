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

        function browser_is_independent_of_acquisition(tc)
            % The browser is a review tool: acquiring must not yank the sweep
            % being examined out from under the operator. The live trace above
            % is what tracks acquisition.
            tc.Win = tc.build();
            for k = 1:3
                tc.Win.Runner.acquireOne();
            end
            tc.verifyFalse(any(contains(tc.panelTitles(), 'Sweep browser — sweep')), ...
                'the browser must not jump to sweeps as they arrive');

            tc.Win.browseStep(+1);
            tc.verifyTrue(any(contains(tc.panelTitles(), 'Sweep browser — sweep 1')));
            tc.Win.browseStep(+1);
            tc.verifyTrue(any(contains(tc.panelTitles(), 'Sweep browser — sweep 2')));
            tc.Win.browseStep(-1);
            tc.verifyTrue(any(contains(tc.panelTitles(), 'Sweep browser — sweep 1')));

            % Acquiring again leaves the browser where the operator put it.
            tc.Win.Runner.acquireOne();
            tc.verifyTrue(any(contains(tc.panelTitles(), 'Sweep browser — sweep 1')));

            % Past the ends it holds, rather than erroring (legacy behaviour).
            tc.Win.browseStep(-5);
            tc.verifyTrue(any(contains(tc.panelTitles(), 'Sweep browser — sweep 1')));
        end

        function preview_limits_never_sit_on_the_trace(tc)
            % A stimulus rests at 0 for most of the sweep; limits taken from
            % min/max would put that baseline on the axis edge, hiding it.
            lims = sem.gui.StimPanel.paddedLimits([0 0 0.4 0.4 0]');
            tc.verifyLessThan(lims(1), 0);
            tc.verifyGreaterThan(lims(2), 0.4);

            % A negative-going command (the test pulse) is padded on both sides.
            lims = sem.gui.StimPanel.paddedLimits([0 0 -5 -5 0]');
            tc.verifyLessThan(lims(1), -5);
            tc.verifyGreaterThan(lims(2), 0);

            % An all-zero trace still gets a real span, not a degenerate one.
            lims = sem.gui.StimPanel.paddedLimits(zeros(10, 1));
            tc.verifyGreaterThan(lims(2), lims(1));
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

        function hold_axes_limits_survives_changing_sweep(tc)
            % Zoom in on a sweep, tick Hold axes limits, step to another sweep:
            % the view must stay put. cla and plot both reset the limits, so
            % they have to be captured before the axes is touched.
            tc.Win = tc.build();
            for k = 1:3
                tc.Win.Runner.acquireOne();
            end
            tc.Win.browseStep(+1);

            ax = tc.Win.browseAxesForTest();
            zoomX = [0.05 0.12];
            zoomY = [100 200];
            xlim(ax, zoomX); ylim(ax, zoomY);
            tc.Win.setHoldAxesLimits(true);

            tc.Win.browseStep(+1);   % next sweep

            tc.verifyEqual(xlim(ax), zoomX, 'AbsTol', 1e-9, ...
                'changing sweep discarded the held x limits');
            tc.verifyEqual(ylim(ax), zoomY, 'AbsTol', 1e-9, ...
                'changing sweep discarded the held y limits');

            % Unticking lets it autoscale to the sweep again.
            tc.Win.setHoldAxesLimits(false);
            tc.Win.browseStep(-1);
            tc.verifyNotEqual(xlim(ax), zoomX);
        end

        function trend_x_axis_grows_in_ten_minute_blocks(tc)
            % A window that rescaled to the data would flatten a slow drift.
            tc.Win = tc.build();
            tc.Win.Runner.acquireOne();
            rsAx = tc.Win.trendAxesForTest();
            tc.verifyEqual(xlim(rsAx), [0 10], 'AbsTol', 1e-9);

            % Fake a long session: the window steps to the next whole block.
            tc.Win.setTrendSpanForTest(12.5);
            tc.verifyEqual(xlim(rsAx), [0 20], 'AbsTol', 1e-9);
            tc.Win.setTrendSpanForTest(21);
            tc.verifyEqual(xlim(rsAx), [0 30], 'AbsTol', 1e-9);
        end

        function every_left_hand_plot_shows_its_units(tc)
            tc.Win = tc.build();
            labels = tc.Win.leftAxisLabelsForTest();
            tc.verifyFalse(any(cellfun(@isempty, labels)), ...
                'every plot on the left must name its units');

            % And the mode-dependent ones follow the clamp mode.
            tc.Win.setClampMode('IC');
            labels = tc.Win.leftAxisLabelsForTest();
            tc.verifyTrue(any(contains(labels, 'Vm (mV)')));
            tc.Win.setClampMode('VC');
            labels = tc.Win.leftAxisLabelsForTest();
            tc.verifyTrue(any(contains(labels, 'Im (pA)')));
        end

        function save_as_defaults_round_trips(tc)
            store = sem.gui.stimDefaults('path');
            hadStore = isfile(store);
            if hadStore
                backup = [store '.testbak'];
                copyfile(store, backup);
                tc.addTeardown(@() movefile(backup, store));
            else
                tc.addTeardown(@() deleteIfPresent(store));
            end

            sem.gui.stimDefaults('save', 'led', struct('startTimeMs', 42, ...
                'nPulses', 7, 'pulseDurationMs', 3, 'amplitude', 1.25, ...
                'frequencyHz', 33));
            got = sem.gui.stimDefaults('load', 'led');
            tc.verifyEqual(got.amplitude, 1.25, 'AbsTol', 1e-9);
            tc.verifyEqual(got.nPulses, 7);

            % A new window opens with the saved values, not the built-ins.
            tc.Win = tc.build();
            s = tc.Win.LedPanel.spec();
            tc.verifyEqual(s.amplitude, 1.25, 'AbsTol', 1e-9);
            tc.verifyEqual(s.startTimeMs, 42, 'AbsTol', 1e-9);
        end

        function holding_buttons_queue_and_apply_only_on_start(tc)
            % The amplifier owns holding. Pressing a button must not change it
            % under a sweep in flight - it queues a request that Start applies.
            tc.Win = tc.build();
            tc.Win.Telegraph.setHolding(-70);

            tc.Win.requestHoldingForTest(10);
            tc.verifyEqual(tc.Win.Telegraph.getHolding(), -70, 'AbsTol', 1e-9, ...
                'the button must not write the amplifier immediately');

            tc.Win.Runner.acquireOne();   % Start path applies the request
            tc.verifyEqual(tc.Win.Telegraph.getHolding(), -70, 'AbsTol', 1e-9);

            tc.Win.startForTest();
            tc.Win.Runner.stop();
            tc.verifyEqual(tc.Win.Telegraph.getHolding(), 10, 'AbsTol', 1e-9, ...
                'Start must apply a queued holding request');
        end

        function start_leaves_holding_alone_when_no_button_was_pressed(tc)
            % The whole point: software reads holding, it does not impose one.
            tc.Win = tc.build();
            tc.Win.Telegraph.setHolding(-55);

            tc.Win.startForTest();
            tc.Win.Runner.stop();

            tc.verifyEqual(tc.Win.Telegraph.getHolding(), -55, 'AbsTol', 1e-9, ...
                'Start must not overwrite the operator''s holding');
            tc.verifyTrue(contains(tc.Win.holdingLabelForTest(), '-55'), ...
                'the read-out must show what the amplifier reported');
        end

        function sweep_command_never_adds_holding(tc)
            % A command that carried holding would double it against the
            % amplifier's own. The command must rest at zero deviation.
            tc.Win = tc.build();
            tc.Win.Telegraph.setHolding(-70);
            tc.Win.Runner.acquireOne();

            s = tc.Win.Runner.lastSweep;
            tc.verifyEqual(s.cellCmd(1), 0, 'AbsTol', 1e-9);
            tc.verifyEqual(s.cellCmd(end), 0, 'AbsTol', 1e-9);
            tc.verifyEqual(s.holdingCommandMv, -70, 'AbsTol', 1e-9);
        end

        function window_close_button_shuts_everything_down(tc)
            % Hitting the window's close box must actually close it, releasing
            % the DAQ, rather than leaving a dead window on screen.
            tc.Win = tc.build();
            fig = tc.Win.Figure;
            close(fig);
            tc.verifyFalse(isvalid(fig));
        end

        function closing_mid_run_stops_the_loop(tc)
            % Closing while free-running must stop the sweep loop, not leave a
            % timer firing into deleted widgets.
            tc.Win = tc.build();
            fig = tc.Win.Figure;
            tc.Win.startForTest();
            waitFor(@() tc.Win.Runner.sweepCount >= 1, 10);

            close(fig);
            pause(0.4);   % let any queued timer callback fire post-close

            tc.verifyFalse(isvalid(fig));
            tc.verifyEqual(tc.Win.Runner.state, 'Idle');
        end

        function closing_the_mapping_window_leaves_the_parent_open(tc)
            tc.Win = tc.build();
            tc.Win.openMapping();
            mapFig = tc.Win.MappingWindow.Figure;

            close(mapFig);

            tc.verifyFalse(isvalid(mapFig));
            tc.verifyTrue(isvalid(tc.Win.Figure), ...
                'closing the mapping window must not close the acquisition window');
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

% --- local helpers ---------------------------------------------------------

function waitFor(predicate, timeoutS)
t0 = tic;
while ~predicate() && toc(t0) < timeoutS
    pause(0.02);
end
end

function deleteIfPresent(p)
if isfile(p)
    delete(p);
end
end
