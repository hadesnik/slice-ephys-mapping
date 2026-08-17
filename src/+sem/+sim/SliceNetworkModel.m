classdef SliceNetworkModel < handle
    %SliceNetworkModel Ground-truth slice network for mock ephys synthesis.
    %   Holds a known connectivity (per-cell opsin gains, excitatory weights
    %   W_E onto the patched cell, polysynaptic inhibitory couplings) plus a
    %   passive-membrane model of the patched cell, and synthesizes the
    %   patched cell's response in CELL UNITS (pA in VC, mV in IC/CC) to
    %   (a) arbitrary command waveforms (passive arm: seal tests, holding
    %   steps — biophysics lifted from patchclamp.hardware.FakeBackend) and
    %   (b) optogenetic ensemble stimulation events (evoked arm).
    %
    %   The whole point of this class is the mock roundtrip: exportGroundTruth
    %   writes the true weights, and the Python regression must recover them
    %   from sessions synthesized here. Construct via
    %   sem.sim.makeGroundTruthNetwork (seeded, config-driven).
    %
    %   Sign conventions (VC): inward currents are negative. Excitatory
    %   reversal EeMv = 0, inhibitory EiMv = -70. W_E is defined as EPSC
    %   charge (pC, positive number) per presynaptic spike AT -70 mV; the
    %   driving-force scale maps it to other holdings (at +10 the residual
    %   EPSC flips outward). W_I analogously is IPSC charge per unit
    %   population drive AT +10 mV (zero at -70, the E reversal... i.e. the
    %   I reversal equals the E holding, so I vanishes in E blocks).

    properties (SetAccess = private)
        nCells = 0
        cellIds = []          % 1 x nCells
        dmdXY = []            % nCells x 2, [col row] soma positions on the DMD
        opsinGain = []        % nCells x 1, expected spikes at fill=1, laserVoltsRef
        wE = []               % nCells x 1, EPSC charge pC per spike at -70 (0 = unconnected)
        releaseProb = []      % nCells x 1
        cI = []               % nCells x 1, coupling into the inhibitory pathway
        params = struct()     % kernels, latencies, passive membrane, noise, reversals
        gain = struct()       % sem.util.Units gain struct (for DAQ-volt conversion by callers)
        seed = NaN
    end

    properties (Access = private)
        rng_                  % RandStream, advanced per synthesis call
    end

    methods
        function obj = SliceNetworkModel(spec)
            %SliceNetworkModel Construct from a fully-populated spec struct.
            %   spec fields: nCells, cellIds, opsinGain, wE, releaseProb, cI,
            %   params, gain, seed. Use sem.sim.makeGroundTruthNetwork.
            required = {'nCells','cellIds','dmdXY','opsinGain','wE','releaseProb', ...
                        'cI','params','gain','seed'};
            for i = 1:numel(required)
                if ~isfield(spec, required{i})
                    error('sem:sim:SliceNetworkModel:badSpec', ...
                        'spec is missing field ''%s''.', required{i});
                end
            end
            obj.nCells      = spec.nCells;
            obj.cellIds     = spec.cellIds(:).';
            obj.dmdXY       = spec.dmdXY;
            obj.opsinGain   = spec.opsinGain(:);
            obj.wE          = spec.wE(:);
            obj.releaseProb = spec.releaseProb(:);
            obj.cI          = spec.cI(:);
            obj.params      = spec.params;
            obj.gain        = spec.gain;
            obj.seed        = spec.seed;
            obj.rng_        = RandStream('mt19937ar', 'Seed', spec.seed);
        end

        function ai = synthesizePassive(obj, cmdCellUnits, mode, fs)
            %synthesizePassive Patched-cell response to a command trace.
            %   ai = synthesizePassive(cmdCellUnits, mode, fs) takes the full
            %   command waveform in cell units (VC: mV at the cell; IC: pA
            %   injected) and returns the AI trace in cell units (VC: pA;
            %   IC: mV), noise-free. Vectorized (filter-based IIRs) so
            %   minute-scale 20 kHz sessions synthesize quickly.
            p = obj.params;
            cmd = cmdCellUnits(:);
            n = numel(cmd);
            if n == 0
                ai = zeros(0, 1);
                return
            end
            dt = 1 / fs;
            if strcmp(char(mode), 'VC')
                % Ohmic steady state through Rin: mV/MOhm = nA -> *1000 pA.
                steady = (cmd - p.vrestMv) ./ p.rinMohm * 1000;
                % Capacitive transient at each command edge: peak dV/Rs (pA),
                % decaying with tau = Rs*Cm (MOhm*pF = us).
                tauSec = p.rsMohm * p.cmPf * 1e-6;
                decay = exp(-dt / tauSec);
                edgesMv = [cmd(1); diff(cmd)];
                peakPa = edgesMv ./ p.rsMohm * 1000;
                capTransient = filter(1, [1, -decay], peakPa);
                ai = steady + capTransient;
            else
                % Leaky-integrator membrane: tau_m = Rin*Cm (MOhm*pF = us).
                driveMv = p.vrestMv + cmd .* p.rinMohm / 1000;  % MOhm*pA = uV -> /1000 mV
                tauSec = p.rinMohm * p.cmPf * 1e-6;
                alpha = 1 - exp(-dt / tauSec);
                v0 = p.vrestMv;
                ai = filter(alpha, [1, -(1 - alpha)], driveMv, (1 - alpha) * v0);
            end
        end

        function snippet = synthesizeEvoked(obj, ev, clampState, fs, nWin)
            %synthesizeEvoked Evoked response to one photostim event.
            %   snippet = synthesizeEvoked(ev, clampState, fs, nWin) returns
            %   an nWin x 1 cell-unit snippet starting at the stim onset
            %   sample. ev: struct with kind, cellIds (member ids),
            %   fillFractions, laserVolts, durS, and optionally centroids
            %   (Mx2 DMD [col row] of the stimulation disks). clampState:
            %   struct with mode ('VC'|'IC') and holdingMv. Consumes the
            %   model RandStream (spike draws, release failures, jitter).
            %
            %   Spatial sensitivity: when ev.centroids is present, each
            %   member's optical drive is scaled by a Gaussian of the
            %   distance between its stimulation disk and its soma
            %   (sigma = params.ppsfSigmaUm) — this is the ground-truth
            %   lateral PPSF that exp_slice_ppsf measures.
            %
            %   ev.kind 'direct' models DIRECT opsin photocurrent in the
            %   patched cell (the PPSF measurement); all other kinds model
            %   synaptic drive from presynaptic members.
            p = obj.params;
            snippet = zeros(nWin, 1);
            if isempty(ev) || ~isfield(ev, 'cellIds') || isempty(ev.cellIds)
                return
            end
            [tf, rows] = ismember(ev.cellIds(:), obj.cellIds(:));
            rows = rows(tf);
            fills = ev.fillFractions(:);
            fills = fills(tf);
            laserScale = ev.laserVolts / p.laserVoltsRef;

            % Per-member spatial drive scale from stim-disk-to-soma distance.
            nMembers = numel(rows);
            driveScale = ones(nMembers, 1);
            if isfield(ev, 'centroids') && ~isempty(ev.centroids)
                cen = ev.centroids(tf, :);
                for m = 1:nMembers
                    dPx = norm(cen(m, :) - obj.dmdXY(rows(m), :));
                    dUm = dPx * p.umPerDmdPx;
                    driveScale(m) = exp(-dUm^2 / (2 * p.ppsfSigmaUm^2));
                end
            end

            if strcmp(char(ev.kind), 'direct')
                snippet = obj.synthesizeDirect(ev, clampState, fs, nWin, ...
                    rows, fills, laserScale, driveScale);
                return
            end

            % --- Presynaptic spikes per member cell ---------------------------
            spikeCounts = zeros(nMembers, 1);
            spikeTimesS = cell(nMembers, 1);
            for m = 1:nMembers
                k = rows(m);
                drive = obj.opsinGain(k) * fills(m) * laserScale * driveScale(m);
                meanSpikes = min(p.maxSpikesPerPulse, drive);
                nSpk = floor(meanSpikes);
                if rand(obj.rng_) < (meanSpikes - nSpk)
                    nSpk = nSpk + 1;
                end
                spikeCounts(m) = nSpk;
                t = (p.spikeLatencyMs + p.spikeJitterMs * randn(obj.rng_, nSpk, 1)) / 1000 ...
                    + (0:nSpk-1)' * 0.004;   % refractory spacing for multi-spike bursts
                spikeTimesS{m} = max(t, 5e-4);
            end

            % --- Driving-force scales (W_E defined at -70, W_I at +10) --------
            if strcmp(char(clampState.mode), 'VC')
                vm = clampState.holdingMv;
            else
                vm = p.vrestMv;
            end
            eScale = (vm - p.eeMv) / (-70 - p.eeMv);   % 1 at -70; small & flipped at +10
            iScale = (vm - p.eiMv) / (10 - p.eiMv);    % 1 at +10; 0 at -70

            % --- Monosynaptic EPSCs -------------------------------------------
            iSyn = zeros(nWin, 1);   % pA, signed
            for m = 1:nMembers
                k = rows(m);
                if obj.wE(k) <= 0 || spikeCounts(m) == 0
                    continue
                end
                for s = 1:spikeCounts(m)
                    if rand(obj.rng_) > obj.releaseProb(k)
                        continue   % release failure
                    end
                    t0 = spikeTimesS{m}(s) + p.monoLatencyMs / 1000;
                    iSyn = iSyn - obj.wE(k) * eScale ...
                        * obj.kernel(t0, p.epscTauRMs, p.epscTauDMs, fs, nWin);
                end
            end

            % --- Polysynaptic IPSC (population-drive pathway) -----------------
            popDrive = sum(obj.cI(rows) .* spikeCounts);
            if popDrive > 0 && iScale ~= 0
                t0 = (p.diLatencyMs + p.diJitterMs * abs(randn(obj.rng_))) / 1000;
                chargePc = p.wIGainPc * popDrive;
                iSyn = iSyn + chargePc * iScale ...
                    * obj.kernel(t0, p.ipscTauRMs, p.ipscTauDMs, fs, nWin);
            end

            if strcmp(char(clampState.mode), 'VC')
                snippet = iSyn;
            else
                % CC: integrate synaptic current through the membrane, add
                % stereotyped APs on threshold crossings. iSyn sign flips:
                % inward (negative) current depolarizes.
                tauSec = p.rinMohm * p.cmPf * 1e-6;
                alpha = 1 - exp(-(1/fs) / tauSec);
                dVm = filter(alpha, [1, -(1 - alpha)], -iSyn .* p.rinMohm / 1000);
                snippet = dVm;
                vmAbs = p.vrestMv + dVm;
                aboveIdx = find(vmAbs > p.spikeThresholdMv);
                if ~isempty(aboveIdx)
                    apLen = max(2, round(0.002 * fs));
                    ap = p.apAmplitudeMv * (1 - abs(linspace(-1, 1, apLen)))';
                    sIdx = aboveIdx([true; diff(aboveIdx) > apLen]);  % one AP per crossing
                    for a = 1:numel(sIdx)
                        i0 = sIdx(a);
                        i1 = min(nWin, i0 + apLen - 1);
                        snippet(i0:i1) = snippet(i0:i1) + ap(1:(i1 - i0 + 1));
                    end
                end
            end
        end

        function sigma = noiseSigma(obj, mode)
            %noiseSigma Baseline noise RMS in cell units for the given mode.
            if strcmp(char(mode), 'VC')
                sigma = obj.params.noiseRmsPa;
            else
                sigma = obj.params.noiseRmsMv;
            end
        end

        function s = rngState(obj)
            %rngState Snapshot the seeded stream (see setRngState).
            s = obj.rng_.State;
        end

        function setRngState(obj, s)
            %setRngState Restore a stream snapshot.
            %   Exists so speculative, display-only synthesis (MockEphysDAQ's
            %   peekContinuousAi) cannot advance the stream and perturb the
            %   session's ground truth: every evoked response draws from this
            %   stream, so an extra draw would change all later trials.
            obj.rng_.State = s;
        end

        function noise = drawNoise(obj, n, mode)
            %drawNoise n x 1 Gaussian baseline noise in cell units (seeded stream).
            noise = obj.noiseSigma(mode) * randn(obj.rng_, n, 1);
        end

        function gt = exportGroundTruth(obj)
            %exportGroundTruth The contract consumed by the Python roundtrip.
            %   W_E_eff / W_I_eff are the expected evoked charge (pC) per unit
            %   fill fraction of each cell at the reference laser voltage —
            %   the quantity a linear regression on the fill-fraction design
            %   matrix estimates.
            expSpikesFullFill = min(obj.params.maxSpikesPerPulse, obj.opsinGain);
            gt = struct();
            gt.seed        = obj.seed;
            gt.cellIds     = obj.cellIds;
            gt.opsinGain   = obj.opsinGain;
            gt.W_E_pC      = obj.wE;
            gt.releaseProb = obj.releaseProb;
            gt.cI          = obj.cI;
            gt.W_E_eff     = obj.wE .* obj.releaseProb .* expSpikesFullFill;
            gt.W_I_eff     = obj.params.wIGainPc .* obj.cI .* expSpikesFullFill;
            gt.params      = obj.params;
        end
    end

    methods (Access = private)
        function snippet = synthesizeDirect(obj, ev, clampState, fs, nWin, ...
                rows, fills, laserScale, driveScale)
            %synthesizeDirect Direct opsin photocurrent in the patched cell.
            %   Square-ish photocurrent during the light pulse (exponential
            %   rise/decay edges), amplitude directPeakPa at full drive,
            %   scaled by the cell's relative opsin expression. VC: current
            %   in pA (inward negative). CC: integrated to Vm with threshold
            %   spikes — this is what the PPSF factorial measures.
            p = obj.params;
            iPhoto = zeros(nWin, 1);
            tauOn = 0.001;  tauOff = 0.003;
            t = (0:nWin-1)' / fs;
            onMask = t < ev.durS;
            riseCurve = 1 - exp(-t(onMask) / tauOn);
            for m = 1:numel(rows)
                k = rows(m);
                relOpsin = obj.opsinGain(k) / max(p.opsinGainMean, eps);
                amp = p.directPeakPa * relOpsin * fills(m) * laserScale * driveScale(m);
                if amp <= 0
                    continue
                end
                wave = zeros(nWin, 1);
                wave(onMask) = amp * riseCurve;
                offIdx = find(~onMask, 1);
                if ~isempty(offIdx)
                    peakVal = wave(max(1, offIdx - 1));
                    wave(offIdx:end) = peakVal * exp(-(t(offIdx:end) - ev.durS) / tauOff);
                end
                iPhoto = iPhoto + wave;
            end
            % Small trial-to-trial gain noise (channel-count stochasticity).
            iPhoto = iPhoto * (1 + 0.05 * randn(obj.rng_));

            if strcmp(char(clampState.mode), 'VC')
                snippet = -iPhoto;   % inward current, negative by convention
            else
                tauSec = p.rinMohm * p.cmPf * 1e-6;
                alpha = 1 - exp(-(1/fs) / tauSec);
                dVm = filter(alpha, [1, -(1 - alpha)], iPhoto .* p.rinMohm / 1000);
                snippet = dVm;
                vmAbs = p.vrestMv + dVm;
                aboveIdx = find(vmAbs > p.spikeThresholdMv);
                if ~isempty(aboveIdx)
                    apLen = max(2, round(0.002 * fs));
                    ap = p.apAmplitudeMv * (1 - abs(linspace(-1, 1, apLen)))';
                    sIdx = aboveIdx([true; diff(aboveIdx) > 3 * apLen]);
                    for a = 1:numel(sIdx)
                        i0 = sIdx(a);
                        i1 = min(nWin, i0 + apLen - 1);
                        snippet(i0:i1) = snippet(i0:i1) + ap(1:(i1 - i0 + 1));
                    end
                end
            end
        end

        function k = kernel(~, t0S, tauRMs, tauDMs, fs, nWin)
            %kernel Difference-of-exponentials PSC kernel, unit charge (pA*s = pC).
            %   Onset at t0S seconds into the window; integral == 1 so the
            %   caller multiplies by charge in pC directly.
            t = (0:nWin-1)' / fs - t0S;
            t(t < 0) = NaN;
            tauR = tauRMs / 1000;
            tauD = tauDMs / 1000;
            k = exp(-t / tauD) - exp(-t / tauR);
            k(isnan(k)) = 0;
            k = k / (tauD - tauR);   % analytic integral of the difference
        end
    end
end
