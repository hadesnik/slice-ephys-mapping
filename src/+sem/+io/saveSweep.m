function trialPath = saveSweep(sweep, sweepDir, config, metadata)
%saveSweep Write one free-running sweep in this repo's trial format.
%   trialPath = sem.io.saveSweep(sweep, sweepDir, config, metadata)
%
%   Sweeps are saved as trials, through the same tfp.io.saveTrial the mapping
%   blocks use, so the Python analysis pipeline reads acquisition sweeps with
%   no new reader. metadata.ephys carries the gains snapshot and the clamp
%   mode, and kind is 'sweep' to distinguish these from block trials.
%
%   sweep is the struct sem.acq.SweepRunner publishes: index, ai (CELL UNITS),
%   cellCmd, led, layout, seal, mode, sampleRateHz, timeMin.
%
%   NOTE ON UNITS: aiData on disk is DAQ VOLTS everywhere in this repo, with
%   metadata.ephys.gains as the single conversion source. The runner works in
%   cell units for display and analysis, so this converts back on the way out
%   rather than inventing a second on-disk convention.
%
%   metadata (optional) is the experiment metadata struct from the GUI —
%   genotype, age, virus and so on. Char only: no string/datetime/table may
%   reach a saved field Python reads.

if nargin < 4
    metadata = struct();
end
if ~isfolder(sweepDir)
    mkdir(sweepDir);
end

eCfg = sem.util.configField(config, 'ephys', struct());
dCfg = sem.util.configField(config, 'daq', struct());
gains = sem.util.Units.gainFromConfig(eCfg);
modeC = char(sweep.mode);

tr = tfp.trial.Trial();
tr.trialIdx = sweep.index;
tr.targetSpec = struct('cellIds', [], 'dmdCoords', zeros(0, 2));
tr.powerMw = 0;
tr.duration_s = numel(sweep.ai) / sweep.sampleRateHz;
tr.preStim_s = 0;
tr.postStim_s = 0;
tr.pulseTrain = struct('nPulses', 0, 'interPulse_s', 0, 'pulseWidth_s', 0);

meta = struct();
meta.ephys = struct( ...
    'schemaVersion',    1, ...
    'kind',             'sweep', ...
    'clampMode',        modeC, ...
    'holdingSource',    'software', ...
    'gains',            gains, ...
    'scaledUnits',      scaledUnits(modeC), ...
    'aiChannelMap',     struct('scaledOutput', scaledCol(dCfg)), ...
    'sampleRate',       sweep.sampleRateHz, ...
    'sweepTimeMin',     sweep.timeMin, ...
    'rsMohm',           sweep.seal.rsMohm, ...
    'riMohm',           sweep.seal.riMohm, ...
    'holding',          sweep.seal.holding, ...
    'holdingUnit',      char(sweep.seal.holdingUnit));
meta.experiment = charify(metadata);
tr.metadata = meta;

% Back to DAQ volts for storage, matching every other record in this repo.
aiVolts = sem.util.Units.scaledCellToDaqVolts(sweep.ai, modeC, gains);
tr.markRunning(uint64(1), sweep.sampleRateHz, datetime('now'));
tr.markComplete(struct('aiData', aiVolts), numel(aiVolts));

trialPath = tfp.io.saveTrial(tr, sweepDir);
end

function u = scaledUnits(modeC)
if strcmp(modeC, 'VC')
    u = 'pA';
else
    u = 'mV';
end
end

function c = scaledCol(dCfg)
aiChans = sem.util.configField(dCfg, 'analogInChannels', []);
scaledChan = sem.util.configField(dCfg, 'ai_scaledOutput', 0);
idx = find(aiChans == scaledChan, 1);
if isempty(idx)
    c = NaN;
else
    c = idx;
end
end

function s = charify(s)
%charify No string/datetime/table may reach a saved field Python reads.
if ~isstruct(s)
    s = struct();
    return
end
f = fieldnames(s);
for k = 1:numel(f)
    v = s.(f{k});
    if isstring(v) || ischar(v)
        s.(f{k}) = char(v);
    elseif isdatetime(v)
        s.(f{k}) = char(string(v));
    end
end
end
