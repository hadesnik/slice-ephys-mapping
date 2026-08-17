%run_gui_mock Launch the slice-ephys GUI against a fully simulated rig.
%
%   Everything is simulated: a mock DMD, a mock DAQ, and a seeded
%   SliceNetworkModel standing in for the patched cell and its network. No
%   hardware is touched, so this runs anywhere (macOS included).
%
%   Usage, from the repo root:
%       run(fullfile('scripts','run_gui_mock.m'))
%
%   What you get:
%     Patch tab      Press Start. Seal-test sweeps repeat at ~2/s: the trace
%                    shows the capacitive transient and the trends fill in
%                    Rs / Ri / holding. Ground truth is config.groundTruth
%                    (rsMohm 12, rinMohm 150, vrestMv -65), so the recovered
%                    numbers should land near those. Press Stop to end.
%     Experiment tab Pick the block and press Start block. Trials advance with
%                    live per-trial traces and a seal-test trend; Abort stops
%                    at the next trial boundary and still saves a valid
%                    partial block.
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

% Build the app first: it creates the mock rig and attaches the simulated
% slice (targets + ground-truth network) on its own.
app = sem.gui.SliceEphysApp(config, 'SessionDir', sessionDir);

% Then hand the Experiment tab a block to run, built from the same simulated
% targets the app is using so the ensembles address real cells.
ens = sem.protocol.generateEnsembles(app.Targets, config, 20260817);
config.ensemble.blocks = {'VC-70'};
plans = sem.protocol.planBlocks(ens, app.Targets, config);
app.setBlockPlans(num2cell(plans));

fprintf('\nSimulated rig ready.\n');
fprintf('  Patched cell : %d of %d simulated cells\n', ...
    app.Targets.patchedCellId, numel(app.Targets.cells));
fprintf('  Ground truth : Rs %.0f MOhm, Rin %.0f MOhm, Vrest %.0f mV\n', ...
    app.Model.params.rsMohm, app.Model.params.rinMohm, app.Model.params.vrestMv);
fprintf('  Block        : %s, %d trials\n', plans(1).label, numel(plans(1).trials));
fprintf('  Session dir  : %s\n\n', sessionDir);
fprintf('Patch tab: press Start for the live membrane test.\n');
fprintf('Experiment tab: press Start block to run the mapping block.\n\n');
