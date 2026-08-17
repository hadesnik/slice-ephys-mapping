classdef Seal
    % Seal  Per-trial seal-test analysis: Rs (VC only), Ri, holding/Vrest.
    %
    % Pure-function analyzer. Operates on a single trial's AI samples already in
    % cell units (pA in VC, mV in IC) -- the caller (ExperimentRunner) is
    % responsible for the DAQ-volts to cell-unit conversion via
    % patchclamp.analysis.Units.scaledDaqVoltsToCell (claude.md invariant 1).
    %
    % The seal-test step is additive on top of the front-panel holding command
    % (auto-mode decision A3 in tasks.md): the baseline before the step reflects
    % the cell's holding/Vrest, and the step amplitude is the configured
    % sealTest.amplitudeVcMv (VC) or sealTest.amplitudeIcPa (IC).
    %
    % Algorithms (architecture.md sec.8, spec sec.10d):
    %   holding       = mean of first 10 samples
    %   baselineMean  = mean of the last 20 ms before step onset
    %   steadyStep    = mean of the last 30 ms of the step (skipping the
    %                   capacitive transient after step onset)
    %   Ri (MOhm)     = |stepAmplitude / (steadyStep - baselineMean)| * 1000
    %                   (units: mV / pA = GOhm, * 1000 = MOhm; in IC, pA / mV)
    %   Rs (VC only)  = |stepAmplitude / (peakDeviation - baselineMean)| * 1000
    %                   where peakDeviation is the sample within 5 ms of step
    %                   onset whose absolute deviation from baseline is largest.
    %
    % Sign convention: Rs and Ri are reported as positive MOhm.

    methods (Static)
        function result = analyzeTrial(aiCellUnits, mode, sealTestStruct, sampleRateHz, layoutIndices)
            arguments
                aiCellUnits      (:,1) double
                mode             (1,1) string {mustBeMember(mode, ["VC","IC"])}
                sealTestStruct   struct
                sampleRateHz     (1,1) double {mustBePositive}
                layoutIndices    struct = struct()
            end

            fs = sampleRateHz;
            nSamples = numel(aiCellUnits);

            % --- Compute layout indices if not supplied --------------------------------
            preSamples  = round(sealTestStruct.preMs  / 1000 * fs);
            stepSamples = round(sealTestStruct.stepMs / 1000 * fs);

            if isfield(layoutIndices, 'sealTestStartIdx')
                sealStart = layoutIndices.sealTestStartIdx;
            else
                sealStart = 1;
            end
            if isfield(layoutIndices, 'sealTestStepStartIdx')
                stepStart = layoutIndices.sealTestStepStartIdx;
            else
                stepStart = sealStart + preSamples;
            end
            if isfield(layoutIndices, 'sealTestStepEndIdx')
                stepEnd = layoutIndices.sealTestStepEndIdx;
            else
                stepEnd = stepStart + stepSamples - 1;
            end

            % Clamp into the trace.
            stepStart = max(1, min(stepStart, nSamples));
            stepEnd   = max(stepStart, min(stepEnd, nSamples));

            % --- Holding / Vrest -------------------------------------------------------
            nHold = min(10, nSamples);
            holding = mean(aiCellUnits(1:nHold));

            if mode == "VC"
                holdingUnit = "pA";
            else
                holdingUnit = "mV";
            end

            % --- Baseline (last 20 ms before step onset) -------------------------------
            baselineWindowSamples = round(20 / 1000 * fs);
            baselineWindowSamples = max(1, min(baselineWindowSamples, stepStart - 1));
            if baselineWindowSamples >= 1 && (stepStart - 1) >= 1
                bStart = max(1, stepStart - baselineWindowSamples);
                bEnd   = max(bStart, stepStart - 1);
                baselineMean = mean(aiCellUnits(bStart:bEnd));
            else
                baselineMean = holding;
            end

            % --- Steady-state of step (last 30 ms, skipping the transient) -------------
            stepMs = sealTestStruct.stepMs;
            % Skip the first (stepMs - 30) ms of the step where the capacitive
            % transient lives; clamp so short steps still leave a steady window.
            afterTransientOffsetMs = max(stepMs - 30, stepMs / 2);
            transientSamples = round(afterTransientOffsetMs / 1000 * fs);
            ssStart = min(stepEnd, stepStart + transientSamples);
            ssEnd   = stepEnd;
            if ssEnd >= ssStart
                steadyStepMean = mean(aiCellUnits(ssStart:ssEnd));
            else
                steadyStepMean = baselineMean;
            end
            deltaSteady = steadyStepMean - baselineMean;

            % --- Step amplitude in cell units ------------------------------------------
            if mode == "VC"
                stepCellUnits = sealTestStruct.amplitudeVcMv;
            else
                stepCellUnits = sealTestStruct.amplitudeIcPa;
            end

            % --- Ri --------------------------------------------------------------------
            % VC: stepCellUnits is mV, deltaSteady is pA -> mV/pA = GOhm, *1000 = MOhm.
            % IC: stepCellUnits is pA, deltaSteady is mV -> mV/pA = GOhm, *1000 = MOhm.
            %     The arithmetic is the same |numerator/denominator|*1000 either way,
            %     but the "physical" numerator (mV) and denominator (pA) swap roles.
            if deltaSteady == 0 || ~isfinite(deltaSteady)
                riMohm = NaN;
            else
                if mode == "VC"
                    riMohm = abs(stepCellUnits / deltaSteady) * 1000;
                else
                    riMohm = abs(deltaSteady / stepCellUnits) * 1000;
                end
            end

            % --- Rs (VC only) ----------------------------------------------------------
            if mode == "VC"
                peakWindowSamples = round(5 / 1000 * fs);
                pStart = stepStart;
                pEnd   = min(stepEnd, stepStart + peakWindowSamples);
                pEnd   = min(pEnd, nSamples);
                if pEnd >= pStart
                    window = aiCellUnits(pStart:pEnd);
                    deviations = window - baselineMean;
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

            % --- Pack result -----------------------------------------------------------
            result = struct( ...
                'rsMohm',      rsMohm, ...
                'riMohm',      riMohm, ...
                'holding',     holding, ...
                'holdingUnit', holdingUnit, ...
                'mode',        mode);
        end
    end
end
