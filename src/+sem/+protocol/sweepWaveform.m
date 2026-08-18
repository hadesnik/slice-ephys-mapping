function [cellCmdCellUnits, ledVolts, layout] = sweepWaveform(sweepCfg, mode, fs)
%sweepWaveform Compose one acquisition sweep: cell command + light output.
%   [cellCmd, ledVolts, layout] = sem.protocol.sweepWaveform(sweepCfg, mode, fs)
%
%   One sweep is:
%     cell command = [optional membrane test pulse] + [command pulse train]
%     light output = [LED pulse train]
%   with every train free to start anywhere in the sweep, which is what the
%   acquisition GUI's two stimulus panels express.
%
%   cellCmdCellUnits is in CELL UNITS (mV in VC, pA in IC) and is a DEVIATION
%   FROM HOLDING, not an absolute level: it starts and ends at 0. The caller
%   converts to DAQ volts through sem.util.Units. ledVolts is raw volts, because
%   there is no amplifier in the light path.
%
%   THE AMPLIFIER OWNS HOLDING. The experimenter sets it on the MultiClamp
%   Commander; software reads it to display and record, and writes it only on an
%   explicit request (the GUI's -70 / +10 mV buttons). Software must never add
%   holding to the analog-out on top of what the Commander is already applying,
%   or a cell held at -70 would sit at -140. Everything here is therefore a
%   deviation that rides on the front-panel level, which is also what the legacy
%   acquisition did (its test pulse was additive, with the DAQ resting at 0).
%
%   sweepCfg fields (all optional except durationS):
%     durationS          sweep length, seconds
%     testPulse          logical, include the membrane test (default true)
%     testPulseStartMs   ms from sweep start (default 50, the legacy value)
%     sealTest_*         flat seal-test keys, read by sem.protocol.sealTestWaveform
%     command            struct, a sem.protocol.pulseTrain spec in cell units
%     led                struct, a sem.protocol.pulseTrain spec in volts
%
%   layout carries the test-pulse sample indices under the names
%   sem.analysis.sealAnalysis already expects (sealTestStartIdx,
%   sealTestStepStartIdx, sealTestStepEndIdx), so the seal maths has exactly
%   one implementation in this repo, plus the two trains' onsets for display.
%
%   See also sem.protocol.pulseTrain, sem.protocol.sealTestWaveform,
%   sem.analysis.sealAnalysis.

modeC = char(mode);
if ~ismember(modeC, {'VC', 'IC'})
    error('sem:protocol:sweepWaveform:badMode', ...
        'mode must be ''VC'' or ''IC''; got ''%s''.', modeC);
end
if ~isnumeric(fs) || ~isscalar(fs) || ~isfinite(fs) || fs <= 0
    error('sem:protocol:sweepWaveform:badRate', 'fs must be a positive finite scalar.');
end

durationS = sem.util.configField(sweepCfg, 'durationS', 1.0);
if ~isfinite(durationS) || durationS <= 0
    error('sem:protocol:sweepWaveform:badDuration', ...
        'sweepCfg.durationS must be a positive finite scalar.');
end
nSamples = max(1, round(fs * durationS));

layout = struct('nSamples', nSamples, 'sampleRateHz', fs, ...
    'sealTestStartIdx', NaN, 'sealTestStepStartIdx', NaN, ...
    'sealTestStepEndIdx', NaN, 'commandOnsetIdx', [], 'ledOnsetIdx', []);

% --- Cell command: a deviation from the amplifier's holding -------------
cellCmdCellUnits = zeros(nSamples, 1);
useTestPulse = logical(sem.util.configField(sweepCfg, 'testPulse', true));
if useTestPulse
    [sealCell, sealLayout] = sem.protocol.sealTestWaveform(sweepCfg, modeC, fs);
    startMs = sem.util.configField(sweepCfg, 'testPulseStartMs', 50);
    s0 = max(1, round(startMs * fs / 1000) + 1);
    s1 = min(nSamples, s0 + numel(sealCell) - 1);
    if s1 >= s0
        % sealTestWaveform is already a deviation relative to holding, which
        % is exactly what this line carries.
        cellCmdCellUnits(s0:s1) = sealCell(1:(s1 - s0 + 1));
        layout.sealTestStartIdx     = s0;
        layout.sealTestStepStartIdx = s0 + sealLayout.stepStartIdx - 1;
        layout.sealTestStepEndIdx   = s0 + sealLayout.stepEndIdx - 1;
    end
end

% --- Cell command: the command train, summed on top --------------------
cmdSpec = sem.util.configField(sweepCfg, 'command', struct());
if ~isempty(cmdSpec)
    [cmdWave, cmdInfo] = sem.protocol.pulseTrain(cmdSpec, fs, durationS);
    cellCmdCellUnits = cellCmdCellUnits + cmdWave;
    layout.commandOnsetIdx = cmdInfo.onsetIdx;
end

% --- Light output ------------------------------------------------------
ledSpec = sem.util.configField(sweepCfg, 'led', struct());
if isempty(ledSpec)
    ledVolts = zeros(nSamples, 1);
else
    [ledVolts, ledInfo] = sem.protocol.pulseTrain(ledSpec, fs, durationS);
    layout.ledOnsetIdx = ledInfo.onsetIdx;
end

% Both lines end at zero: the command returns to the amplifier's holding
% (the AO idles at its last written sample, and 0 deviation IS holding), and
% the light source cannot be left on between sweeps.
cellCmdCellUnits(max(1, nSamples - 9):nSamples) = 0;
ledVolts(max(1, nSamples - 9):nSamples) = 0;
end
