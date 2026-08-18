%run_gui_mock Launch the acquisition GUI against a fully simulated rig.
%
%   Everything is simulated: a mock DMD, a mock DAQ, and a seeded
%   SliceNetworkModel standing in for the patched cell and its network. No
%   hardware is touched, so this runs anywhere (macOS included).
%
%   Usage, from the repo root:
%       run(fullfile('scripts','run_gui_mock.m'))
%
%   What you get, in one window laid out like the lab's legacy Acq:
%     Start      free-running sweeps at the ISI shown. The live trace shows
%                the membrane test, and Rs / Holding / Rin fill in as trend
%                strips with numeric readouts in their titles. Ground truth is
%                config.groundTruth (rsMohm 12, rinMohm 150, vrestMv -65), so
%                the readouts should land near those. Stop ends it, Pause
%                holds without losing the sweep history.
%     Single     acquire exactly one sweep.
%     Seal test  strips the stimulus and repeats a short membrane test, for
%                use while approaching and sealing.
%     Stimulus   the LED and cell-command panels each have their full
%                parameter set, an Update button and a preview of the NEXT
%                sweep. Editing a field does nothing until you press Update.
%     Mapping…   opens the DMD ensemble / PPSF block run in its own window.
%
%   The session writes to a timestamped folder under data/ (gitignored).
%
%   NOTE: the mock's clock is wall time, so a block runs in real time —
%   nEnsembles below is kept small deliberately. Raise it for a longer run.

run(fullfile(fileparts(fileparts(mfilename('fullpath'))), 'sem_setup.m'));

repoRoot = fileparts(fileparts(mfilename('fullpath')));
config = tfp.io.loadConfig(fullfile(repoRoot, 'configs', 'mock.yaml'));

% A small, quick simulated session. The mock runs in wall-clock time, so keep
% the trial count low unless you want to sit through it.
config.groundTruth.nCells = 12;
config.ensemble.nEnsembles = 20;
config.ensemble.sizeMin = 2;
config.ensemble.sizeMax = 5;
config.ensemble.nBlank = 2;
config.ephys.sealTest_everyNTrials = 10;
config.timing.itiMeanS = 0.05;
config.timing.itiJitterS = 0.02;
config.dmd.chunkSize = 25;
config.ui.liveFigure = false;   % the GUI is the live display now

sessionDir = fullfile(repoRoot, 'data', ...
    ['gui_mock_' datestr(now, 'yyyymmdd_HHMMSS')]); %#ok<TNOW1,DATST>

% The window creates the mock rig and attaches the simulated slice (targets +
% ground-truth network) on its own. Mapping blocks are built from those same
% targets when you press Mapping.
config.ensemble.blocks = {'VC-70'};
app = sem.gui.AcqWindow(config, 'SessionDir', sessionDir);

fprintf('\nSimulated rig ready.\n');
fprintf('  Patched cell : %d of %d simulated cells\n', ...
    app.Targets.patchedCellId, numel(app.Targets.cells));
fprintf('  Ground truth : Rs %.0f MOhm, Rin %.0f MOhm, Vrest %.0f mV\n', ...
    app.Model.params.rsMohm, app.Model.params.rinMohm, app.Model.params.vrestMv);
fprintf('  Session dir  : %s\n\n', sessionDir);
fprintf('Press Start for the live membrane test; Mapping... for a block run.\n\n');
