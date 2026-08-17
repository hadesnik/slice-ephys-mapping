classdef SealTest
    % SealTest  Build the 0..200 ms seal-test segment of a trial.
    %
    % The segment is laid out as three contiguous epochs:
    %   [ pre baseline | step | post baseline ]
    % All values are in cell units (mV in VC, pA in IC); the DAQ backend is
    % responsible for converting to volts using the live telegraph gain.
    %
    % See architecture.md sec.3 (trial structure) and claude.md invariant 1
    % (units at the boundary are cell units).

    methods (Static)
        function [ao0_cellUnits, samplesPerEpoch] = build(sealTestStruct, mode, sampleRateHz)
            arguments
                sealTestStruct (1,1) struct
                mode (1,1) string {mustBeMember(mode, ["VC", "IC"])}
                sampleRateHz (1,1) double {mustBePositive, mustBeInteger}
            end

            patchclamp.config.TrialConfig.validateSealTest(sealTestStruct);

            preSamples  = round(sealTestStruct.preMs  * 1e-3 * sampleRateHz);
            stepSamples = round(sealTestStruct.stepMs * 1e-3 * sampleRateHz);
            postSamples = round(sealTestStruct.postMs * 1e-3 * sampleRateHz);

            if mode == "VC"
                stepAmplitude = sealTestStruct.amplitudeVcMv;
            else
                stepAmplitude = sealTestStruct.amplitudeIcPa;
            end

            ao0_cellUnits = zeros(preSamples + stepSamples + postSamples, 1);
            stepStartIdx = preSamples + 1;
            stepEndIdx   = preSamples + stepSamples;
            ao0_cellUnits(stepStartIdx:stepEndIdx) = stepAmplitude;

            samplesPerEpoch = struct( ...
                'preSamples',   preSamples, ...
                'stepSamples',  stepSamples, ...
                'postSamples',  postSamples, ...
                'stepStartIdx', stepStartIdx, ...
                'stepEndIdx',   stepEndIdx);
        end
    end
end
