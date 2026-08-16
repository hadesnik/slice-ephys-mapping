%run_mock_session Generate the seeded mock E/I session for the Python roundtrip.
%   Runs a full exp_ensemble_ei mock session (ground-truth network -> VC-70 +
%   VC+10 blocks, identical ensembles replayed) into data/mock_session_<seed>/.
%   Takes a few minutes of wall clock (the mock DAQ clock is real time).
%
%   Then, from analysis/:
%       .venv/bin/python -m pytest tests/test_mock_roundtrip.py -v
%
%   Usage (from the repo root):
%       run(fullfile('scripts', 'run_mock_session.m'))

thisDir = fileparts(mfilename('fullpath'));
run(fullfile(thisDir, '..', 'sem_setup.m'));

SEED = 20260816;

config = tfp.io.loadConfig(fullfile(thisDir, '..', 'configs', 'mock.yaml'));
config.paths.dataDir = fullfile(thisDir, '..', 'data');

% Roundtrip-scale overrides: enough ensembles to constrain 25 cells well,
% ITI long enough that PSC tails clear the next trial's analysis window.
config.groundTruth.nCells = 25;
config.ensemble.nEnsembles = 600;
config.ensemble.nBlank = 40;
config.ensemble.sizeMin = 5;
config.ensemble.sizeMax = 15;
config.ensemble.blocks = {'VC-70', 'VC+10'};
config.timing.itiMeanS = 0.08;
config.timing.itiJitterS = 0.02;
config.ephys.sealTest_everyNTrials = 100;
config.ui.liveFigure = false;

sessionName = sprintf('mock_session_%d', SEED);
fprintf('Running mock E/I session -> %s (this takes a few minutes)...\n', sessionName);
t0 = tic;
result = sem.experiments.exp_ensemble_ei(config, sessionName, struct('seed', SEED));
fprintf('Done in %.1f s. Session dir:\n  %s\n', toc(t0), result.sessionDir);
fprintf('Now validate from analysis/:\n  .venv/bin/python -m pytest tests/test_mock_roundtrip.py -v\n');
