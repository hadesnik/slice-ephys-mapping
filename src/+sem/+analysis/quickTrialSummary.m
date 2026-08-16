function summary = quickTrialSummary(trial, config)
%quickTrialSummary On-rig quick-look metrics for one completed trial.
%   summary = sem.analysis.quickTrialSummary(trial, config)
%
%   Converts the scaled-output AI column to cell units via the trial's own
%   gains snapshot and computes rough response metrics — enough for live
%   sanity checks and experiment-level result tables. The rigorous versions
%   (charge integration, CV, regression) live in the Python package.
%
%   summary fields: ok, peakAbsResponse (|peak - baseline| in cell units),
%   baselineMean, responseSign, nSpikes (CC only; NaN in VC), units.

summary = struct('ok', false, 'peakAbsResponse', NaN, 'baselineMean', NaN, ...
    'responseSign', 0, 'nSpikes', NaN, 'units', '');
if ~strcmp(trial.status, 'complete') || ~isstruct(trial.data) ...
        || ~isfield(trial.data, 'aiData') || isempty(trial.data.aiData)
    return
end
eMeta = trial.metadata.ephys;
col = eMeta.aiChannelMap.scaledOutput;
if isnan(col) || size(trial.data.aiData, 2) < col
    return
end
fs = trial.daq_master_sample_rate_hz;
onsetIn = eMeta.stimOnsetSampleInSnippet;
if isnan(onsetIn) || isnan(fs)
    return
end

ai = sem.util.Units.scaledDaqVoltsToCell(trial.data.aiData(:, col), ...
    eMeta.clampMode, eMeta.gains);
n = numel(ai);

baseEnd = max(1, round(onsetIn) - 1);
baselineMean = mean(ai(1:baseEnd));

respWinS = sem.util.configField( ...
    sem.util.configField(config, 'timing', struct()), 'postS', 0.15);
r0 = min(n, round(onsetIn) + round(0.002 * fs));
r1 = min(n, round(onsetIn) + round(respWinS * fs));
if r1 <= r0
    return
end
resp = ai(r0:r1) - baselineMean;
[peakAbs, iPeak] = max(abs(resp));

nSpikes = NaN;
if strcmp(eMeta.clampMode, 'IC')
    % Count upward 0 mV crossings (the mock's APs overshoot well past 0).
    vm = ai(r0:r1);
    above = vm > 0;
    nSpikes = nnz(diff(above) == 1) + double(above(1));
end

summary.ok = true;
summary.peakAbsResponse = peakAbs;
summary.baselineMean = baselineMean;
summary.responseSign = sign(resp(iPeak));
summary.nSpikes = nSpikes;
summary.units = eMeta.scaledUnits;
end
