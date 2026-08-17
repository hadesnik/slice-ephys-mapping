classdef Trial
    % Trial  Compose the full per-trial AO0 (command) and AO2 (LED) waveforms.
    %
    % Timeline (architecture.md sec.3, auto-mode decision A3):
    %   [ seal-test  | pause | stimulus window ]
    %     0..endST     ..300ms  300ms..end
    %
    % AO0 is in cell units (mV in VC, pA in IC). AO2 is in volts.
    % Conversion of AO0 to DAQ volts happens later in the DAQ backend, not here
    % (claude.md invariant 1).

    properties (Constant)
        % Fixed start of the stimulus window, per architecture.md sec.3.
        STIMULUS_WINDOW_START_MS = 300
    end

    methods (Static)
        function [ao0_cellUnits, ao2_volts, layout] = compose(trialConfig, mode)
            arguments
                trialConfig (1,1) struct
                mode (1,1) string {mustBeMember(mode, ["VC", "IC"])}
            end

            patchclamp.config.TrialConfig.validate(trialConfig);

            sampleRateHz = trialConfig.sampleRateHz;
            totalSamples = round(trialConfig.trialLengthSec * sampleRateHz);

            stimWindowStartIdx = round(patchclamp.protocol.Trial.STIMULUS_WINDOW_START_MS * 1e-3 * sampleRateHz) + 1;
            stimWindowEndIdx   = totalSamples;
            stimWindowSamples  = stimWindowEndIdx - stimWindowStartIdx + 1;
            stimWindowSec      = stimWindowSamples / sampleRateHz;

            if stimWindowSamples <= 0
                error("patchclamp:protocol:Trial:trialTooShort", ...
                    "Trial length %.4f s is shorter than the fixed %d ms preamble.", ...
                    trialConfig.trialLengthSec, ...
                    patchclamp.protocol.Trial.STIMULUS_WINDOW_START_MS);
            end

            % Seal-test segment.
            [sealTestSegment, sealEpochs] = patchclamp.protocol.SealTest.build( ...
                trialConfig.sealTest, mode, sampleRateHz);

            sealTestStartIdx = 1;
            sealTestEndIdx   = numel(sealTestSegment);

            if sealTestEndIdx >= stimWindowStartIdx
                error("patchclamp:protocol:Trial:sealTestOverrunsPreamble", ...
                    "Seal-test segment is %d samples but the preamble ends at sample %d.", ...
                    sealTestEndIdx, stimWindowStartIdx - 1);
            end

            ao0_cellUnits = zeros(totalSamples, 1);
            ao0_cellUnits(sealTestStartIdx:sealTestEndIdx) = sealTestSegment;

            ao2_volts = zeros(totalSamples, 1);

            % Command-side stimulus.
            if ~isempty(trialConfig.commandStim)
                if mode == "VC"
                    cmdUnit = "mV";
                else
                    cmdUnit = "pA";
                end
                cmdWaveform = patchclamp.protocol.PulseTrain.build( ...
                    trialConfig.commandStim, sampleRateHz, stimWindowSec, cmdUnit);
                ao0_cellUnits(stimWindowStartIdx:stimWindowEndIdx) = cmdWaveform;
            end

            % Opto stimulus.
            if ~isempty(trialConfig.opto)
                optoWaveform = patchclamp.protocol.PulseTrain.build( ...
                    trialConfig.opto, sampleRateHz, stimWindowSec, "percent");
                ao2_volts(stimWindowStartIdx:stimWindowEndIdx) = optoWaveform;
            end

            layout = struct( ...
                'sealTestStartIdx',       sealTestStartIdx, ...
                'sealTestEndIdx',         sealTestEndIdx, ...
                'sealTestStepStartIdx',   sealEpochs.stepStartIdx, ...
                'sealTestStepEndIdx',     sealEpochs.stepEndIdx, ...
                'stimulusWindowStartIdx', stimWindowStartIdx, ...
                'stimulusWindowEndIdx',   stimWindowEndIdx);
        end
    end
end
