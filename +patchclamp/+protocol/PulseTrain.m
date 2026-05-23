classdef PulseTrain
    % PulseTrain  Build a parametric pulse-train waveform.
    %
    % Output units:
    %   amplitudeUnit == "mV" or "pA"  -> waveform is in cell units, flows through unchanged.
    %   amplitudeUnit == "percent"     -> waveform is in volts via LedDriver.brightnessPercentToVolts.
    %
    % Each pulse holds at `amplitude` for `pulseDurationMs` then returns to 0
    % until the next pulse onset, which is spaced by `1/frequencyHz`. The full
    % waveform length matches the caller-supplied stimulus window (typically
    % trialLengthSec - 300 ms).

    methods (Static)
        function [waveform, info] = build(pulseTrainStruct, sampleRateHz, windowDurationSec, amplitudeUnit)
            arguments
                pulseTrainStruct (1,1) struct
                sampleRateHz (1,1) double {mustBePositive, mustBeInteger}
                windowDurationSec (1,1) double {mustBePositive}
                amplitudeUnit (1,1) string {mustBeMember(amplitudeUnit, ["mV", "pA", "percent"])}
            end

            patchclamp.config.PulseTrainConfig.validate(pulseTrainStruct);
            patchclamp.config.PulseTrainConfig.validateFitsWindow(pulseTrainStruct, windowDurationSec);

            % LED driver is the only path that requires a unit conversion here;
            % validate the percent value through it so the operating range is
            % enforced in exactly one place (claude.md: conversions live in one place).
            if amplitudeUnit == "percent"
                amplitudeVolts = patchclamp.hardware.LedDriver.brightnessPercentToVolts(pulseTrainStruct.amplitude);
                pulseValue = amplitudeVolts;
            else
                pulseValue = pulseTrainStruct.amplitude;
            end

            nSamples = round(windowDurationSec * sampleRateHz);
            waveform = zeros(nSamples, 1);

            pulseOnSamples = round(pulseTrainStruct.pulseDurationMs * 1e-3 * sampleRateHz);
            periodSamples  = round((1 / pulseTrainStruct.frequencyHz) * sampleRateHz);

            pulseStartIdx = zeros(pulseTrainStruct.nPulses, 1);
            pulseEndIdx   = zeros(pulseTrainStruct.nPulses, 1);

            for k = 1:pulseTrainStruct.nPulses
                startIdx = (k - 1) * periodSamples + 1;
                endIdx   = startIdx + pulseOnSamples - 1;
                if endIdx > nSamples
                    endIdx = nSamples;
                end
                waveform(startIdx:endIdx) = pulseValue;
                pulseStartIdx(k) = startIdx;
                pulseEndIdx(k)   = endIdx;
            end

            info = struct( ...
                'nSamples',       nSamples, ...
                'pulseOnSamples', pulseOnSamples, ...
                'periodSamples',  periodSamples, ...
                'pulseStartIdx',  pulseStartIdx, ...
                'pulseEndIdx',    pulseEndIdx, ...
                'amplitudeUnit',  amplitudeUnit);
        end
    end
end
