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
%   cellCmdCellUnits is in CELL UNITS (mV in VC, pA in IC), ABSOLUTE: it
%   includes the holding level, and the sweep both starts and ends there. The
%   caller converts to DAQ volts through sem.util.Units. ledVolts is raw volts,
%   because there is no amplifier in the light path.
%
%   HOLDING IS COMMANDED IN SOFTWARE, which assumes the MultiClamp Commander's
%   own holding is 0. That is the convention sem.protocol.EpisodicRunner already
%   uses for mapping blocks and that every trial records as
%   metadata.ephys.holdingSource = 'software'. Patch sweeps follow it so the two
%   modes cannot disagree: if sweeps left holding to the front panel while
%   blocks commanded it in software, patching a cell at -70 mV and then starting
%   a block would hold it at -140.
%
%   sweepCfg fields (all optional except durationS):
%     durationS          sweep length, seconds
%     holdingMv          holding level in cell units (mV in VC, pA in IC);
%                        default 0, which is also the correct IC value
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

% --- Cell command: holding, then the test pulse on top -----------------
holding = sem.util.configField(sweepCfg, 'holdingMv', 0);
if ~isfinite(holding)
    holding = 0;
end
layout.holdingMv = holding;
cellCmdCellUnits = repmat(holding, nSamples, 1);
useTestPulse = logical(sem.util.configField(sweepCfg, 'testPulse', true));
if useTestPulse
    [sealCell, sealLayout] = sem.protocol.sealTestWaveform(sweepCfg, modeC, fs);
    startMs = sem.util.configField(sweepCfg, 'testPulseStartMs', 50);
    s0 = max(1, round(startMs * fs / 1000) + 1);
    s1 = min(nSamples, s0 + numel(sealCell) - 1);
    if s1 >= s0
        % sealTestWaveform returns a deviation RELATIVE to holding, so it adds
        % onto the holding level rather than replacing it.
        cellCmdCellUnits(s0:s1) = holding + sealCell(1:(s1 - s0 + 1));
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

% The cell command ends AT HOLDING, not at zero: the NI AO idles at its last
% written sample, so this is what keeps the cell held between sweeps (the same
% convention EpisodicRunner uses). The light line ends at zero so the source
% cannot be left on.
cellCmdCellUnits(max(1, nSamples - 9):nSamples) = holding;
ledVolts(max(1, nSamples - 9):nSamples) = 0;
end
