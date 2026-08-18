function previewTrial(mode)
    % previewTrial  Open a figure showing one composed trial and the FakeBackend's
    % synthesised AI response. Standalone dev-time visualiser; not part of the app.
    %
    %   previewTrial()        % defaults to "VC"
    %   previewTrial("IC")
    arguments
        mode (1,1) string {mustBeMember(mode, ["VC", "IC"])} = "VC"
    end

    cfg = patchclamp.config.TrialConfig.defaultConfig();
    cfg.mode = mode;

    cmd = patchclamp.config.PulseTrainConfig.defaultConfig();
    if mode == "VC"
        cmd.amplitude = 10;     % +10 mV test pulses
    else
        cmd.amplitude = 50;     % +50 pA current injections
    end
    cfg.commandStim = cmd;

    opto = patchclamp.config.PulseTrainConfig.defaultConfig();
    opto.amplitude       = 80;  % 80% LED
    opto.pulseDurationMs = 2;
    opto.frequencyHz     = 20;
    opto.nPulses         = 10;
    cfg.opto = opto;

    [ao0, ao2, layout] = patchclamp.protocol.Trial.compose(cfg, mode);

    telegraph = patchclamp.hardware.FakeTelegraph(mode = mode);
    backend = patchclamp.hardware.FakeBackend(telegraph, rngSeed = 0);
    backend.configureTrial(ao0, ao2, "ai1", cfg.sampleRateHz, cfg.trialLengthSec);
    ai = backend.run();

    t = (0:numel(ao0)-1).' / cfg.sampleRateHz * 1000;  % ms

    if mode == "VC"
        cmdUnit = "mV"; aiUnit = "pA";
    else
        cmdUnit = "pA"; aiUnit = "mV";
    end

    fig = uifigure(Name = sprintf("previewTrial (%s)", mode), Position = [100 100 900 700]);
    g = uigridlayout(fig, [3 1]);
    g.RowHeight = {'1x','1x','1.5x'};

    ax1 = uiaxes(g); plot(ax1, t, ao0, 'b'); grid(ax1,'on');
    title(ax1, sprintf("AO0 command (%s)", cmdUnit));
    ylabel(ax1, cmdUnit);

    ax2 = uiaxes(g); plot(ax2, t, ao2, 'Color', [0.85 0.6 0]); grid(ax2,'on');
    title(ax2, "AO2 LED (V)");
    ylabel(ax2, "V");

    ax3 = uiaxes(g); plot(ax3, t, ai, 'k'); grid(ax3,'on');
    title(ax3, sprintf("AI response, FakeBackend synth (%s)", aiUnit));
    xlabel(ax3, "time (ms)"); ylabel(ax3, aiUnit);

    % Mark the stim-window boundary so seal-test vs stim segments are obvious.
    for ax = [ax1 ax2 ax3]
        xline(ax, (layout.stimulusWindowStartIdx-1)/cfg.sampleRateHz*1000, ...
              '--', 'stim start', LabelHorizontalAlignment = 'left');
    end
end
