classdef FakeBackend < patchclamp.hardware.DAQ
    % FakeBackend  Synthesises a plausible AI trace for macOS dev/test.
    %
    % Implements the patchclamp.hardware.DAQ contract without touching real
    % hardware. The mode and gain are read from a MultiClamp telegraph at run()
    % time (not at configureTrial() time) so a mid-session mode flip on the fake
    % telegraph is reflected by the very next trial -- mirroring the real
    % NidaqBackend, which queries the live telegraph snapshot when arming the AI
    % conversion.
    %
    % Ground-truth biophysics is exposed via tunable public properties so the
    % Round-1 analysis tests can validate Rs / Ri / Vrest recovery against
    % values this object actually synthesised.
    %
    % Physical model:
    %   VC: returns I(t) in pA = baseline + step-response through Rinput
    %       + RC capacitive transient (peak = dV / Rs, tau = Rs * Cm)
    %       + Gaussian noise.
    %   IC: returns V(t) in mV = baseline + Rinput * (Ihold + Vcmd)
    %       low-pass filtered with tau_m = Rinput * Cm
    %       + Gaussian noise.
    %
    % LED (AO2) is recorded only as a mirror in the AO snapshot; it does not
    % perturb the synthesised cell signal in v1.

    properties
        RsMOhm        (1,1) double {mustBeReal, mustBePositive, mustBeFinite} = 15
        RinputMOhm    (1,1) double {mustBeReal, mustBePositive, mustBeFinite} = 150
        CmPicoF       (1,1) double {mustBeReal, mustBePositive, mustBeFinite} = 100
        VrestMv       (1,1) double {mustBeReal, mustBeFinite}                 = -65
        VholdMv       (1,1) double {mustBeReal, mustBeFinite}                 = -70
        IholdPa       (1,1) double {mustBeReal, mustBeFinite}                 = 0
        noiseRmsPaVc  (1,1) double {mustBeReal, mustBeNonnegative, mustBeFinite} = 5
        noiseRmsMvIc  (1,1) double {mustBeReal, mustBeNonnegative, mustBeFinite} = 0.3
        rngSeed       % [] or non-negative integer
    end

    properties (SetAccess = private)
        % Constructor-validated to be a patchclamp.hardware.MultiClamp. No
        % type constraint on the property declaration because MultiClamp is
        % abstract and MATLAB requires an instantiable default value when a
        % class is named here.
        Telegraph
    end

    properties (Access = private)
        Ao0CommandCellUnits double = double.empty
        Ao2LedVolts         double = double.empty
        AiChannelName       (1,1) string = "ai1"
        SampleRateHz        (1,1) double = 0
        DurationSec         (1,1) double = 0
        Configured          (1,1) logical = false
    end

    methods
        function obj = FakeBackend(telegraph, opts)
            arguments
                telegraph (1,1) patchclamp.hardware.MultiClamp
                opts.RsMOhm        = []
                opts.RinputMOhm    = []
                opts.CmPicoF       = []
                opts.VrestMv       = []
                opts.VholdMv       = []
                opts.IholdPa       = []
                opts.noiseRmsPaVc  = []
                opts.noiseRmsMvIc  = []
                opts.rngSeed       = []
            end
            obj.Telegraph = telegraph;
            if ~isempty(opts.RsMOhm),       obj.RsMOhm       = opts.RsMOhm;       end
            if ~isempty(opts.RinputMOhm),   obj.RinputMOhm   = opts.RinputMOhm;   end
            if ~isempty(opts.CmPicoF),      obj.CmPicoF      = opts.CmPicoF;      end
            if ~isempty(opts.VrestMv),      obj.VrestMv      = opts.VrestMv;      end
            if ~isempty(opts.VholdMv),      obj.VholdMv      = opts.VholdMv;      end
            if ~isempty(opts.IholdPa),      obj.IholdPa      = opts.IholdPa;      end
            if ~isempty(opts.noiseRmsPaVc), obj.noiseRmsPaVc = opts.noiseRmsPaVc; end
            if ~isempty(opts.noiseRmsMvIc), obj.noiseRmsMvIc = opts.noiseRmsMvIc; end
            obj.rngSeed = opts.rngSeed;
        end

        function configureTrial(obj, ao0CommandCellUnits, ao2LedVolts, aiChannelName, sampleRateHz, durationSec)
            arguments
                obj
                ao0CommandCellUnits (:,1) double {mustBeReal, mustBeFinite}
                ao2LedVolts         (:,1) double {mustBeReal, mustBeFinite}
                aiChannelName       (1,1) string
                sampleRateHz        (1,1) double {mustBePositive, mustBeFinite}
                durationSec         (1,1) double {mustBePositive, mustBeFinite}
            end

            expectedN = round(sampleRateHz * durationSec);
            if numel(ao0CommandCellUnits) ~= expectedN
                error("patchclamp:hardware:FakeBackend:lengthMismatch", ...
                    "ao0CommandCellUnits has %d samples; expected %d (= sampleRateHz * durationSec).", ...
                    numel(ao0CommandCellUnits), expectedN);
            end
            if numel(ao2LedVolts) ~= expectedN
                error("patchclamp:hardware:FakeBackend:lengthMismatch", ...
                    "ao2LedVolts has %d samples; expected %d (= sampleRateHz * durationSec).", ...
                    numel(ao2LedVolts), expectedN);
            end

            obj.Ao0CommandCellUnits = ao0CommandCellUnits;
            obj.Ao2LedVolts         = ao2LedVolts;
            obj.AiChannelName       = aiChannelName;
            obj.SampleRateHz        = sampleRateHz;
            obj.DurationSec         = durationSec;
            obj.Configured          = true;
        end

        function aiSamplesCellUnits = run(obj)
            if ~obj.Configured
                error("patchclamp:hardware:FakeBackend:notConfigured", ...
                    "run() called before configureTrial().");
            end

            % Snapshot the telegraph live -- the real backend does the same when
            % arming each trial. (architecture.md sec.6, claude.md invariant 3.)
            mode = obj.Telegraph.getMode();

            if ~isempty(obj.rngSeed)
                rngState = rng(obj.rngSeed, "twister");
                cleanup = onCleanup(@() rng(rngState));  %#ok<NASGU>
            end

            fs   = obj.SampleRateHz;
            vcmd = obj.Ao0CommandCellUnits;
            N    = numel(vcmd);
            dt   = 1 / fs;  % seconds

            if mode == "VC"
                aiSamplesCellUnits = obj.synthVc(vcmd, fs, dt, N);
            else
                aiSamplesCellUnits = obj.synthIc(vcmd, dt, N);
            end
        end

        function cleanup(obj)
            obj.Ao0CommandCellUnits = double.empty;
            obj.Ao2LedVolts         = double.empty;
            obj.SampleRateHz        = 0;
            obj.DurationSec         = 0;
            obj.Configured          = false;
        end
    end

    methods (Access = private)
        function I = synthVc(obj, vcmdMv, fs, dt, N)
            % Steady-state Ohmic current driven by (Vhold + Vcmd - Vrest)/Rinput.
            effectiveCellMv     = obj.VholdMv + vcmdMv;
            steadyStateCurrent  = (effectiveCellMv - obj.VrestMv) ./ obj.RinputMOhm .* 1000;  % pA

            % Capacitive transient at each command edge.
            % tau_s in ms (MOhm * pF = us; /1000 -> ms). Convert to seconds for the decay.
            tauSec = obj.RsMOhm * obj.CmPicoF / 1000 / 1000;  % ms -> s
            decayPerSample = exp(-dt / tauSec);

            % Discrete RC kernel for the capacitive arm: each command edge dV
            % injects a peak of dV / Rs pA on the SAME sample, decaying by
            % decayPerSample each subsequent sample. We compute this by
            % integrating an "edge train" through a first-order IIR.
            edgesMv = [vcmdMv(1); diff(vcmdMv)];   % dV at each sample, mV
            peakPa  = edgesMv ./ obj.RsMOhm .* 1000;  % pA peak per edge

            capTransient = zeros(N, 1);
            state = 0;
            for n = 1:N
                state = state * decayPerSample + peakPa(n);
                capTransient(n) = state;
            end

            % Subtract the contribution that the steady-state arm would assign to
            % the initial edge -- otherwise we'd double-count the first sample's
            % jump. The steady-state already handles long-term values; the cap
            % transient handles the fast deviation above steady state.
            noise = obj.noiseRmsPaVc .* randn(N, 1);
            I = steadyStateCurrent + capTransient + noise;
        end

        function V = synthIc(obj, vcmdPa, dt, N)
            effectiveInjectedPa = obj.IholdPa + vcmdPa;
            driveMv             = obj.VrestMv + effectiveInjectedPa .* obj.RinputMOhm ./ 1000;

            baselineMv = obj.VrestMv + obj.IholdPa .* obj.RinputMOhm ./ 1000;

            tauMs  = obj.RinputMOhm * obj.CmPicoF / 1000;  % ms
            tauSec = tauMs / 1000;
            alpha  = 1 - exp(-dt / tauSec);

            V = zeros(N, 1);
            V(1) = baselineMv + alpha * (driveMv(1) - baselineMv);
            for n = 2:N
                V(n) = V(n-1) + alpha * (driveMv(n) - V(n-1));
            end

            V = V + obj.noiseRmsMvIc .* randn(N, 1);
        end
    end
end
