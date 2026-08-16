function [cellUnits, layout] = sealTestWaveform(sealCfg, mode, sampleRateHz)
%sealTestWaveform Build the seal-test command segment in cell units.
%   [cellUnits, layout] = sem.protocol.sealTestWaveform(sealCfg, mode, fs)
%
%   Lifted from the lab's whole-cell patch software (patchclamp.protocol.SealTest).
%   Layout: [ pre baseline | step | post baseline ], all values in cell units
%   (mV in VC, pA in IC) RELATIVE to the current holding level — the caller
%   adds the holding command and converts to DAQ volts via
%   sem.util.Units.commandCellToDaqVolts.
%
%   sealCfg uses the flattened config names: sealTest_preMs, sealTest_stepMs,
%   sealTest_postMs, sealTest_amplitudeVcMv, sealTest_amplitudeIcPa.
%
%   layout: struct with preSamples, stepSamples, postSamples, stepStartIdx,
%   stepEndIdx (indices into cellUnits).

modeC = char(mode);
if ~ismember(modeC, {'VC', 'IC'})
    error('sem:protocol:sealTestWaveform:badMode', ...
        'mode must be ''VC'' or ''IC''; got ''%s''.', modeC);
end
if ~isnumeric(sampleRateHz) || ~isscalar(sampleRateHz) || sampleRateHz <= 0
    error('sem:protocol:sealTestWaveform:badRate', ...
        'sampleRateHz must be a positive scalar.');
end

preMs  = sem.util.configField(sealCfg, 'sealTest_preMs', 20);
stepMs = sem.util.configField(sealCfg, 'sealTest_stepMs', 100);
postMs = sem.util.configField(sealCfg, 'sealTest_postMs', 30);
if any(~isfinite([preMs, stepMs, postMs])) || stepMs <= 0
    error('sem:protocol:sealTestWaveform:badConfig', ...
        'sealTest_{pre,step,post}Ms must be finite with stepMs > 0.');
end

preSamples  = round(preMs  * 1e-3 * sampleRateHz);
stepSamples = round(stepMs * 1e-3 * sampleRateHz);
postSamples = round(postMs * 1e-3 * sampleRateHz);

if strcmp(modeC, 'VC')
    stepAmplitude = sem.util.configField(sealCfg, 'sealTest_amplitudeVcMv', -5);
else
    stepAmplitude = sem.util.configField(sealCfg, 'sealTest_amplitudeIcPa', -20);
end

cellUnits = zeros(preSamples + stepSamples + postSamples, 1);
stepStartIdx = preSamples + 1;
stepEndIdx   = preSamples + stepSamples;
cellUnits(stepStartIdx:stepEndIdx) = stepAmplitude;

layout = struct( ...
    'preSamples',   preSamples, ...
    'stepSamples',  stepSamples, ...
    'postSamples',  postSamples, ...
    'stepStartIdx', stepStartIdx, ...
    'stepEndIdx',   stepEndIdx);
end
