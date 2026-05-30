function snapshotMainWindow(outPng)
% snapshotMainWindow  Build MainWindow, populate the plots with a few
% synthetic trials, and export the whole app to a PNG for layout review.
%
% Headless-friendly: uses a Visible='off' figure and exportapp.

    arguments
        outPng (1,1) string = "mainwindow_snapshot.png"
    end

    here = fileparts(mfilename('fullpath'));
    addpath(genpath(fullfile(here, '..')));

    win = patchclamp.gui.MainWindow('Visible', 'off');

    cfg = win.Config;
    sr  = cfg.sampleRateHz;
    [ao0, ao2, layout] = patchclamp.protocol.Trial.compose(cfg, "VC"); %#ok<ASGLU>
    n = numel(ao0);
    t = (0:n-1)' / sr;

    % A few synthetic trials so every plot has data.
    for k = 1:4
        ai = zeros(n,1);
        % Seal-test ping in the preamble.
        ping = layout.sealTestStepStartIdx:layout.sealTestStepEndIdx;
        ai(ping) = -120 - 8*k;
        % A decaying response in the stimulus window.
        sw = layout.stimulusWindowStartIdx:layout.stimulusWindowEndIdx;
        m  = numel(sw);
        ai(sw) = (40 + 5*k) * exp(-(0:m-1)'/(0.15*m)) .* (1 + 0.05*sin((1:m)'/3));
        ai = ai + 2*randn(n,1);

        r = struct( ...
            'aiCellUnits',        ai, ...
            'aoCommandCellUnits', ao0, ...
            'aoLedVolts',         ao2, ...
            'rsMohm',             18 + 0.4*k, ...
            'riMohm',             220 + 5*k, ...
            'holding',            -45 - k, ...
            'holdingUnit',        "pA", ...
            'mode',               "VC", ...
            'sampleRateHz',       sr, ...
            'timestamp',          string(datetime("now")), ...
            'gainSnapshot',       struct(), ...
            'trialIndex',         uint32(k), ...
            'layout',             layout);

        win.TrialPlotPanel.addTrial(ai, sr, "VC");
        win.StimulusResponsePanel.addTrial(ai, sr, "VC", layout);
        win.TrendPlotsPanel.addTrialResult(r);
    end

    drawnow;
    exportapp(win.Figure, outPng);
    fprintf('Wrote %s\n', outPng);

    win.shutdown();
end
