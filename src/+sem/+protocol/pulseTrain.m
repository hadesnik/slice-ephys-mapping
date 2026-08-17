function [wave, info] = pulseTrain(spec, fs, sweepDurationS)
%pulseTrain Square pulse train over a whole sweep.
%   [wave, info] = sem.protocol.pulseTrain(spec, fs, sweepDurationS)
%
%   The stimulus primitive of the acquisition GUI, one train per output
%   channel. Ported from the lab's legacy makepulseoutputs, keeping its
%   parameter set and units so the on-screen controls mean what they always
%   meant:
%
%     spec.startTimeMs      onset of the FIRST pulse, ms from sweep start
%     spec.nPulses          number of pulses in the train (0 = no stimulus)
%     spec.pulseDurationMs  width of each pulse, ms
%     spec.amplitude        pulse height, in the caller's units (volts for a
%                           light source; pA in IC / mV in VC for the cell
%                           command, which the caller converts afterwards)
%     spec.frequencyHz      train rate. This is the ONSET-TO-ONSET period of
%                           successive pulses, not the gap between them, so
%                           the gap is 1000/frequencyHz - pulseDurationMs ms.
%
%   Two behaviours of the original are deliberately kept:
%     - the last samples of the sweep are forced to zero, so a light source
%       cannot be left on between sweeps;
%     - a train that runs past the end of the sweep is truncated rather than
%       rejected, so turning up the pulse count mid-experiment cannot error
%       out the acquisition loop. info.truncated reports it.
%
%   One behaviour is deliberately NOT kept: the original's 8th argument was
%   documented as an amplitude delta but incremented pulse DURATION (the
%   amplitude line was commented out). Per-sweep stepping lives in the sweep
%   runner here, where it steps the parameter it says it steps.
%
%   info: nSamples, onsetIdx, offsetIdx, periodSamples, truncated.
%
%   See also sem.protocol.sweepWaveform.

if ~isstruct(spec) || ~isscalar(spec)
    error('sem:protocol:pulseTrain:badSpec', 'spec must be a scalar struct.');
end
if ~isnumeric(fs) || ~isscalar(fs) || ~isfinite(fs) || fs <= 0
    error('sem:protocol:pulseTrain:badRate', 'fs must be a positive finite scalar.');
end
if ~isnumeric(sweepDurationS) || ~isscalar(sweepDurationS) ...
        || ~isfinite(sweepDurationS) || sweepDurationS <= 0
    error('sem:protocol:pulseTrain:badDuration', ...
        'sweepDurationS must be a positive finite scalar.');
end

startTimeMs     = sem.util.configField(spec, 'startTimeMs', 0);
nPulses         = sem.util.configField(spec, 'nPulses', 0);
pulseDurationMs = sem.util.configField(spec, 'pulseDurationMs', 0);
amplitude       = sem.util.configField(spec, 'amplitude', 0);
frequencyHz     = sem.util.configField(spec, 'frequencyHz', 1);

nSamples = max(1, round(fs * sweepDurationS));
wave = zeros(nSamples, 1);
info = struct('nSamples', nSamples, 'onsetIdx', [], 'offsetIdx', [], ...
    'periodSamples', NaN, 'truncated', false);

% A zero-pulse, zero-amplitude or zero-width train is the "no stimulus"
% state the Clear buttons produce; it is not an error.
if nPulses <= 0 || amplitude == 0 || pulseDurationMs <= 0
    wave = zeroTail(wave);
    return
end
if ~isfinite(frequencyHz) || frequencyHz <= 0
    error('sem:protocol:pulseTrain:badFrequency', ...
        'frequencyHz must be positive and finite; got %g.', frequencyHz);
end

periodSamples = max(1, round(fs / frequencyHz));
widthSamples  = max(1, round(pulseDurationMs * fs / 1000));
% 0 ms lands on sample 1 (the legacy version indexed from 0 here and errored).
firstIdx = max(1, round(startTimeMs * fs / 1000) + 1);

onsets  = zeros(1, nPulses);
offsets = zeros(1, nPulses);
nPlaced = 0;
for k = 1:nPulses
    i0 = firstIdx + (k - 1) * periodSamples;
    if i0 > nSamples
        info.truncated = true;
        break
    end
    i1 = min(nSamples, i0 + widthSamples - 1);
    if i1 < i0 + widthSamples - 1
        info.truncated = true;
    end
    wave(i0:i1) = amplitude;
    nPlaced = nPlaced + 1;
    onsets(nPlaced) = i0;
    offsets(nPlaced) = i1;
end

info.onsetIdx = onsets(1:nPlaced);
info.offsetIdx = offsets(1:nPlaced);
info.periodSamples = periodSamples;
wave = zeroTail(wave);
end

function w = zeroTail(w)
%zeroTail Force the sweep's tail to zero so an output cannot stick on.
n = numel(w);
w(max(1, n - 9):n) = 0;
end
