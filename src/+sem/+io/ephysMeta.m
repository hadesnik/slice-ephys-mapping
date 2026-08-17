function m = ephysMeta(blockPlan, config, trialSpec)
%ephysMeta Build the metadata.ephys block for one trial.
%   m = sem.io.ephysMeta(blockPlan, config, trialSpec)
%
%   The schema every trial's meta file carries (schemaVersion 1). aiData in
%   the raw file stays in DAQ VOLTS; the gains snapshot recorded here is the
%   single source for unit conversion downstream (Python units.py). All
%   values are plain doubles/chars so v7.3 files stay h5py-readable (no
%   MATLAB string/datetime classes).

eCfg = sem.util.configField(config, 'ephys', struct());
dCfg = sem.util.configField(config, 'daq', struct());
tCfg = sem.util.configField(config, 'timing', struct());

aiChans = sem.util.configField(dCfg, 'analogInChannels', []);
scaledCol = find(aiChans == sem.util.configField(dCfg, 'ai_scaledOutput', 0), 1);
if isempty(scaledCol), scaledCol = NaN; end

if strcmp(blockPlan.mode, 'VC')
    scaledUnits = 'pA';
else
    scaledUnits = 'mV';
end

m = struct();
m.schemaVersion = 1;
m.clampMode = blockPlan.mode;                 % 'VC' | 'IC'
m.holdingMv = blockPlan.holdingMv;            % the holding this block asked for
m.holdingSource = 'amplifier';                % the Commander applies it; the
                                              % analog-out carries deviations
m.blockLabel = blockPlan.label;
m.blockId = blockPlan.blockId;
m.gains = sem.util.Units.gainFromConfig(eCfg);
m.aiChannelMap = struct('scaledOutput', scaledCol);
m.scaledUnits = scaledUnits;
m.stimOnsetSampleInSnippet = NaN;             % filled at finalize
m.stimDurS = sem.util.configField(tCfg, 'stimDurS', 0.010);
m.laserVolts = trialSpec.laserVolts;
m.laserPowerMwEst = NaN;                      % filled when a power cal exists
m.powerNote = 'laserVolts commanded; no power calibration applied';
m.ensembleId = trialSpec.ensembleId;
m.kind = trialSpec.kind;
end
