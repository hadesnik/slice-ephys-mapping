function result = sealAnalysis(aiCellUnits, mode, sealCfg, sampleRateHz, layoutIndices)
%sealAnalysis Per-trial seal-test analysis: Rs (VC only), Ri, holding/Vrest.
%   result = sem.analysis.sealAnalysis(aiCellUnits, mode, sealCfg, fs, layout)
%
%   Pure-function analyzer lifted from the lab's whole-cell patch software
%   (patchclamp.analysis.Seal). Operates on one trial's AI samples already in
%   CELL UNITS (pA in VC, mV in IC) — the caller converts DAQ volts first via
%   sem.util.Units.scaledDaqVoltsToCell.
%
%   sealCfg fields (flattened config names): sealTest_preMs, sealTest_stepMs,
%   sealTest_postMs, sealTest_amplitudeVcMv, sealTest_amplitudeIcPa.
%
%   layoutIndices (optional struct): sealTestStartIdx, sealTestStepStartIdx,
%   sealTestStepEndIdx — sample indices of the seal segment inside
%   aiCellUnits. Defaults assume the segment starts at sample 1.
%
%   Algorithms:
%     holding      = mean of first 10 samples
%     baselineMean = mean of the last 20 ms before step onset
%     steadyStep   = mean of the last 30 ms of the step (skips the transient)
%     Ri (MOhm)    = |stepAmplitude / (steadyStep - baselineMean)| * 1000
%     Rs (VC only) = |stepAmplitude / (peakDeviation - baselineMean)| * 1000
%                    (peak within 5 ms of step onset)
%
%   result: struct with rsMohm, riMohm, holding, holdingUnit, mode.

if nargin < 5
    layoutIndices = struct();
end
aiCellUnits = aiCellUnits(:);
modeC = char(mode);
if ~ismember(modeC, {'VC', 'IC'})
    error('sem:analysis:sealAnalysis:badMode', ...
        'mode must be ''VC'' or ''IC''; got ''%s''.', modeC);
end
fs = sampleRateHz;
nSamples = numel(aiCellUnits);

preMs  = sem.util.configField(sealCfg, 'sealTest_preMs', 20);
stepMs = sem.util.configField(sealCfg, 'sealTest_stepMs', 100);

preSamples  = round(preMs  / 1000 * fs);
stepSamples = round(stepMs / 1000 * fs);

sealStart = sem.util.configField(layoutIndices, 'sealTestStartIdx', 1);
stepStart = sem.util.configField(layoutIndices, 'sealTestStepStartIdx', sealStart + preSamples);
stepEnd   = sem.util.configField(layoutIndices, 'sealTestStepEndIdx', stepStart + stepSamples - 1);

stepStart = max(1, min(stepStart, nSamples));
stepEnd   = max(stepStart, min(stepEnd, nSamples));

% Holding / Vrest: DC level at the very start of the trace.
nHold = min(10, nSamples);
holding = mean(aiCellUnits(1:nHold));
if strcmp(modeC, 'VC')
    holdingUnit = 'pA';
else
    holdingUnit = 'mV';
end

% Baseline: last 20 ms before step onset.
baselineWindowSamples = round(20 / 1000 * fs);
baselineWindowSamples = max(1, min(baselineWindowSamples, stepStart - 1));
if baselineWindowSamples >= 1 && (stepStart - 1) >= 1
    bStart = max(1, stepStart - baselineWindowSamples);
    bEnd   = max(bStart, stepStart - 1);
    baselineMean = mean(aiCellUnits(bStart:bEnd));
else
    baselineMean = holding;
end

% Steady-state of the step: last 30 ms (skip the capacitive transient).
afterTransientOffsetMs = max(stepMs - 30, stepMs / 2);
transientSamples = round(afterTransientOffsetMs / 1000 * fs);
ssStart = min(stepEnd, stepStart + transientSamples);
if stepEnd >= ssStart
    steadyStepMean = mean(aiCellUnits(ssStart:stepEnd));
else
    steadyStepMean = baselineMean;
end
deltaSteady = steadyStepMean - baselineMean;

if strcmp(modeC, 'VC')
    stepCellUnits = sem.util.configField(sealCfg, 'sealTest_amplitudeVcMv', -5);
else
    stepCellUnits = sem.util.configField(sealCfg, 'sealTest_amplitudeIcPa', -20);
end

% Ri: mV/pA = GOhm, *1000 = MOhm (numerator/denominator roles swap in IC but
% the |ratio|*1000 arithmetic is identical).
if deltaSteady == 0 || ~isfinite(deltaSteady)
    riMohm = NaN;
elseif strcmp(modeC, 'VC')
    riMohm = abs(stepCellUnits / deltaSteady) * 1000;
else
    riMohm = abs(deltaSteady / stepCellUnits) * 1000;
end

% Rs (VC only): peak deviation from baseline within 5 ms of step onset.
if strcmp(modeC, 'VC')
    peakWindowSamples = round(5 / 1000 * fs);
    pEnd = min([stepEnd, stepStart + peakWindowSamples, nSamples]);
    if pEnd >= stepStart
        deviations = aiCellUnits(stepStart:pEnd) - baselineMean;
        [~, iMax] = max(abs(deviations));
        deltaPeak = deviations(iMax);
    else
        deltaPeak = 0;
    end
    if deltaPeak == 0 || ~isfinite(deltaPeak)
        rsMohm = NaN;
    else
        rsMohm = abs(stepCellUnits / deltaPeak) * 1000;
    end
else
    rsMohm = NaN;
end

result = struct( ...
    'rsMohm',      rsMohm, ...
    'riMohm',      riMohm, ...
    'holding',     holding, ...
    'holdingUnit', holdingUnit, ...
    'mode',        modeC);
end
