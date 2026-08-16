function [snippet, onsetInSnippet] = sliceSessionAi(sessionData, onsetSample, offsetSample, preS, postS)
%sliceSessionAi Cut one trial's AI snippet out of the continuous session record.
%   [snippet, onsetInSnippet] = sem.io.sliceSessionAi(sessionData, onset,
%   offset, preS, postS)
%
%   sessionData: result struct from stopContinuousSession (.aiData nSamples x
%   nAI, .sampleRate). onset/offset: DAQ sample anchors from queueClockedAO
%   (t_onset/t_offset_daq_samples). preS/postS: baseline and response windows
%   in seconds. Window edges clamp to the record; onsetInSnippet is the
%   1-based row of the stim onset within the returned snippet (feeds
%   metadata.ephys.stimOnsetSampleInSnippet).

fs = sessionData.sampleRate;
nTotal = size(sessionData.aiData, 1);
onset = double(onsetSample);
offset = double(offsetSample);

startIdx = max(1, round(onset - preS * fs));
endIdx = min(nTotal, round(offset + postS * fs));
if endIdx < startIdx
    snippet = zeros(0, size(sessionData.aiData, 2));
    onsetInSnippet = NaN;
    return
end
snippet = sessionData.aiData(startIdx:endIdx, :);
onsetInSnippet = round(onset) - startIdx + 1;
end
