classdef MockEphysDAQ < tfp.hardware.DAQ
    %MockEphysDAQ Simulated DAQ with a patched cell behind the AI channel.
    %   Implements the full tfp.hardware.DAQ contract (MockDAQ's validation
    %   and logging idioms, same contract-level error identifiers) and, when
    %   a sem.sim.SliceNetworkModel is attached, synthesizes the Multiclamp
    %   scaled-output AI channel from ground truth at stopContinuousSession:
    %
    %     1. The cell-command AO column is reconstructed across the whole
    %        session (waveforms pasted at their queued onsets; the line holds
    %        its last written sample between queues, mirroring NI AO idle
    %        behavior) and run through the model's passive-membrane arm —
    %        so seal tests and holding ramps produce recoverable Rs/Ri/DC.
    %     2. Each stim event announced via setActiveStim (paired with the
    %        next queueClockedAO onset) adds the model's evoked EPSC/IPSC/
    %        spike response.
    %     3. Baseline noise is added and everything converts to DAQ volts
    %        via sem.util.Units (the model's gain struct).
    %
    %   Without an attached model the AI is MockDAQ-style noise only.
    %
    %   Mock-only methods (experiments reach them via sem.hardware.notifyStim
    %   and ismethod guards, never directly): attachNetworkModel,
    %   setClampState, setActiveStim, getEvents.

    properties (SetAccess = protected)
        sampleRate = []
        analogInChannels = []
        analogOutChannels = []
        digitalInChannels = []
        digitalOutChannels = []
        isRunning = false
        isInitialized = false
    end

    properties (Access = private)
        model_ = []
        clampState_ = struct('mode', 'VC', 'holdingMv', 0)
        pendingStim_ = []
        events_ = struct('onset', {}, 'samples', {}, 'stim', {}, ...
                         'clampMode', {}, 'holdingMv', {})

        aiScaledChan_ = 0
        aoLaserChan_ = 0
        aoCellCmdChan_ = 1

        configuredAiChannels_ = []
        configuredAoChannels_ = []
        configuredDoLines_ = {}
        configuredDiLines_ = {}
        aiRangeV_ = []
        queuedAo_ = []
        log_ = struct('timestamp', {}, 'eventType', {}, 'payload', {})

        continuousCfg_ = []
        continuousStartTic_ = []
        continuousStartDatetime_ = NaT
        continuousAoSamplesWritten_ = uint64(0)
        continuousFinalSampleCount_ = uint64(0)
        continuousEverStarted_ = false
        sessionClampMode_ = ''
        lastFiniteCmdVolts_ = 0   % AO idle level carried between finite sweeps
    end

    methods
        function initialize(obj, config)
            if ~isstruct(config)
                error('sem:hardware:MockEphysDAQ:badConfig', ...
                    'config must be a struct.');
            end
            obj.sampleRate         = sem.util.configField(config, 'sampleRate', 20000);
            obj.analogInChannels   = sem.util.configField(config, 'analogInChannels', []);
            obj.analogOutChannels  = sem.util.configField(config, 'analogOutChannels', []);
            obj.digitalInChannels  = sem.util.configField(config, 'digitalInChannels', {});
            obj.digitalOutChannels = sem.util.configField(config, 'digitalOutChannels', {});
            obj.aiScaledChan_      = sem.util.configField(config, 'ai_scaledOutput', 0);
            obj.aoLaserChan_       = sem.util.configField(config, 'ao_laser', 0);
            obj.aoCellCmdChan_     = sem.util.configField(config, 'ao_cellCommand', 1);

            obj.isRunning             = false;
            obj.isInitialized         = true;
            obj.queuedAo_             = [];
            obj.configuredAiChannels_ = [];
            obj.configuredAoChannels_ = [];
            obj.configuredDoLines_    = {};
            obj.configuredDiLines_    = {};
            obj.aiRangeV_             = [];
            obj.events_ = struct('onset', {}, 'samples', {}, 'stim', {}, ...
                                 'clampMode', {}, 'holdingMv', {});
            obj.pendingStim_ = [];

            obj.logEvent('initialize', config);
        end

        function attachNetworkModel(obj, model)
            %attachNetworkModel Attach the ground-truth network (mock-only).
            if ~isa(model, 'sem.sim.SliceNetworkModel')
                error('sem:hardware:MockEphysDAQ:badModel', ...
                    'model must be a sem.sim.SliceNetworkModel; got %s.', class(model));
            end
            obj.model_ = model;
            obj.logEvent('attachNetworkModel', struct('seed', model.seed));
        end

        function setClampState(obj, s)
            %setClampState Mirror the operator/software clamp state (mock-only).
            %   s: struct with mode ('VC'|'IC') and holdingMv. The clamp MODE
            %   is frozen for the duration of a continuous session (a real
            %   amplifier's mode is not software-switchable mid-block).
            if ~isstruct(s) || ~isfield(s, 'mode') || ~isfield(s, 'holdingMv')
                error('sem:hardware:MockEphysDAQ:badClampState', ...
                    's must be a struct with fields mode and holdingMv.');
            end
            modeC = char(s.mode);
            if ~ismember(modeC, {'VC', 'IC'})
                error('sem:hardware:MockEphysDAQ:badClampState', ...
                    'mode must be ''VC'' or ''IC''; got ''%s''.', modeC);
            end
            if obj.isRunning && ~strcmp(modeC, obj.sessionClampMode_)
                error('sem:hardware:MockEphysDAQ:modeChangeWhileRunning', ...
                    'clamp mode cannot change during a continuous session.');
            end
            obj.clampState_ = struct('mode', modeC, 'holdingMv', double(s.holdingMv));
            obj.logEvent('setClampState', obj.clampState_);
        end

        function setActiveStim(obj, ev)
            %setActiveStim Announce the stim event paired with the NEXT queueClockedAO.
            %   ev: struct with kind ('ensemble'|'single'|'sealTest'|'blank'),
            %   and for optogenetic kinds: cellIds, fillFractions, laserVolts,
            %   durS.
            if ~isstruct(ev) || ~isfield(ev, 'kind')
                error('sem:hardware:MockEphysDAQ:badStim', ...
                    'ev must be a struct with a ''kind'' field.');
            end
            obj.pendingStim_ = ev;
            obj.logEvent('setActiveStim', struct('kind', ev.kind));
        end

        function events = getEvents(obj)
            %getEvents Recorded (onset, waveform, stim, clamp) event list (tests).
            events = obj.events_;
        end

        function configureAnalogInput(obj, channels, rangeV, singleEndedChannels)
            obj.requireInitialized('configureAnalogInput');
            if nargin < 4
                singleEndedChannels = [];
            end
            if ~all(ismember(channels, obj.analogInChannels))
                error('sem:hardware:MockEphysDAQ:badChannels', ...
                    'channels must be a subset of analogInChannels = [%s]; got [%s].', ...
                    num2str(obj.analogInChannels), num2str(channels));
            end
            obj.configuredAiChannels_ = channels;
            obj.aiRangeV_ = rangeV;
            % Logged so callers can be checked against the real DAQ's contract:
            % NI6323_DAQ sets InputType='SingleEnded' on these, and dropping the
            % argument silently reads the amplifier differentially.
            obj.logEvent('configureAnalogInput', struct('channels', channels, ...
                'rangeV', rangeV, 'singleEnded', singleEndedChannels));
        end

        function configureAnalogOutput(obj, channels)
            obj.requireInitialized('configureAnalogOutput');
            if ~all(ismember(channels, obj.analogOutChannels))
                error('sem:hardware:MockEphysDAQ:badChannels', ...
                    'channels must be a subset of analogOutChannels = [%s]; got [%s].', ...
                    num2str(obj.analogOutChannels), num2str(channels));
            end
            obj.configuredAoChannels_ = channels;
            obj.logEvent('configureAnalogOutput', struct('channels', channels));
        end

        function configureDigitalOutput(obj, lines)
            obj.requireInitialized('configureDigitalOutput');
            linesC = cellstr(lines);
            availC = cellstr(obj.digitalOutChannels);
            if ~all(ismember(linesC, availC))
                error('sem:hardware:MockEphysDAQ:badLines', ...
                    'lines must be a subset of digitalOutChannels.');
            end
            obj.configuredDoLines_ = linesC;
            obj.logEvent('configureDigitalOutput', struct('lines', {linesC}));
        end

        function configureDigitalInput(obj, lines)
            obj.requireInitialized('configureDigitalInput');
            linesC = cellstr(lines);
            availC = obj.digitalInChannels;
            if ~isempty(availC)
                availC = cellstr(availC);
                if ~all(ismember(linesC, availC))
                    error('sem:hardware:MockEphysDAQ:badLines', ...
                        'lines must be a subset of digitalInChannels.');
                end
            end
            obj.configuredDiLines_ = linesC;
            obj.logEvent('configureDigitalInput', struct('lines', {linesC}));
        end

        function queueAnalogOutput(obj, data)
            obj.requireInitialized('queueAnalogOutput');
            if isempty(obj.configuredAoChannels_)
                error('sem:hardware:MockEphysDAQ:noAoConfigured', ...
                    'configureAnalogOutput() required first.');
            end
            nChans = numel(obj.configuredAoChannels_);
            if ~isnumeric(data) || ndims(data) > 2 || size(data, 2) ~= nChans
                error('sem:hardware:MockEphysDAQ:badShape', ...
                    'data must be (nSamples x %d) numeric; got size [%s].', ...
                    nChans, num2str(size(data)));
            end
            obj.queuedAo_ = data;
            obj.logEvent('queueAnalogOutput', struct( ...
                'nSamples', size(data, 1), 'nChans', size(data, 2)));
        end

        function queueDigitalPulses(obj, lineNames, times, durations)
            obj.requireInitialized('queueDigitalPulses');
            lineNamesC = cellstr(lineNames);
            if numel(lineNamesC) ~= numel(times) || numel(lineNamesC) ~= numel(durations)
                error('sem:hardware:MockEphysDAQ:badLengths', ...
                    'lineNames, times, durations must be the same length.');
            end
            obj.logEvent('queueDigitalPulses', struct('nPulses', numel(lineNamesC)));
        end

        function start(obj)
            obj.requireInitialized('start');
            obj.isRunning = true;
            obj.logEvent('start', []);
        end

        function stop(obj)
            obj.isRunning = false;
            obj.queuedAo_ = [];
            obj.logEvent('stop', []);
        end

        function data = readAnalogInput(obj, nSamples)
            obj.requireInitialized('readAnalogInput');
            if isempty(obj.configuredAiChannels_)
                error('sem:hardware:MockEphysDAQ:noAiConfigured', ...
                    'configureAnalogInput() required first.');
            end
            nChans = numel(obj.configuredAiChannels_);
            data = obj.synthesizeFinite(nSamples, nChans);
            obj.logEvent('readAnalogInput', struct('nSamples', nSamples, 'nChans', nChans));
        end

        function data = readDigitalInput(obj, lineName, nSamples)
            obj.requireInitialized('readDigitalInput');
            data = zeros(nSamples, 1);
            obj.logEvent('readDigitalInput', struct( ...
                'lineName', char(lineName), 'nSamples', nSamples));
        end

        function sendDigitalPulse(obj, lineName, durationS)
            obj.requireInitialized('sendDigitalPulse');
            lineNameC = char(lineName);
            if ~any(strcmp(lineNameC, obj.configuredDoLines_))
                error('sem:hardware:MockEphysDAQ:badLines', ...
                    'lineName must be in configuredDoLines.');
            end
            if ~isnumeric(durationS) || ~isscalar(durationS) ...
                    || ~isfinite(durationS) || durationS <= 0
                error('sem:hardware:MockEphysDAQ:badDuration', ...
                    'durationS must be a positive finite numeric scalar.');
            end
            obj.logEvent('sendDigitalPulse', struct( ...
                'lineName', lineNameC, 'durationS', durationS));
        end

        function outputSingleAnalog(obj, channelName, voltageV)
            obj.requireInitialized('outputSingleAnalog');
            if ~isnumeric(voltageV) || ~isscalar(voltageV) || ~isfinite(voltageV)
                error('sem:hardware:MockEphysDAQ:badVoltage', ...
                    'voltageV must be a finite scalar; got %s.', mat2str(voltageV));
            end
            obj.logEvent('outputSingleAnalog', struct( ...
                'channel', char(channelName), 'voltageV', voltageV));
        end

        function startContinuousSession(obj, cfg)
            %startContinuousSession Begin the hardware-clocked session.
            %   Contract errors use the shared tfp:hardware:DAQ:* identifiers
            %   so contract-level tests hold across all DAQ implementations.
            if obj.isRunning
                error('tfp:hardware:DAQ:alreadyRunning', ...
                    'startContinuousSession called while a session is already running.');
            end
            if ~isstruct(cfg) || ~isscalar(cfg)
                error('tfp:hardware:DAQ:badConfig', 'cfg must be a scalar struct.');
            end
            if ~isfield(cfg, 'sampleRate') || ~isnumeric(cfg.sampleRate) ...
                    || ~isscalar(cfg.sampleRate) || ~isfinite(cfg.sampleRate) ...
                    || cfg.sampleRate <= 0
                error('tfp:hardware:DAQ:badConfig', ...
                    'cfg.sampleRate must be a positive finite scalar.');
            end

            snap = struct();
            snap.sampleRate = double(cfg.sampleRate);
            snap.aiChannels = sem.util.configField(cfg, 'aiChannels', []);
            snap.aiRangeV   = sem.util.configField(cfg, 'aiRangeV', []);
            snap.aoChannels = sem.util.configField(cfg, 'aoChannels', []);
            diLinesRaw      = sem.util.configField(cfg, 'diLines', {});
            doLinesRaw      = sem.util.configField(cfg, 'doLines', {});
            if isempty(diLinesRaw), snap.diLines = {}; else, snap.diLines = cellstr(diLinesRaw); end
            if isempty(doLinesRaw), snap.doLines = {}; else, snap.doLines = cellstr(doLinesRaw); end
            snap.frameClockLine = char(sem.util.configField(cfg, 'frameClockLine', ''));

            obj.sampleRate                  = snap.sampleRate;
            obj.continuousCfg_              = snap;
            obj.continuousStartTic_         = tic;
            obj.continuousStartDatetime_    = datetime('now');
            obj.continuousAoSamplesWritten_ = uint64(0);
            obj.continuousFinalSampleCount_ = uint64(0);
            obj.continuousEverStarted_      = true;
            obj.isRunning                   = true;
            obj.sessionClampMode_           = obj.clampState_.mode;
            obj.events_ = struct('onset', {}, 'samples', {}, 'stim', {}, ...
                                 'clampMode', {}, 'holdingMv', {});

            obj.logEvent('startContinuousSession', snap);
        end

        function startSampleIdx = queueClockedAO(obj, samples, rate, startTrigger)
            if ~obj.isRunning || isempty(obj.continuousCfg_)
                error('tfp:hardware:DAQ:notRunning', ...
                    'queueClockedAO requires an active continuous session.');
            end
            snap = obj.continuousCfg_;
            nAo = numel(snap.aoChannels);
            if ~isnumeric(samples) || ndims(samples) > 2 || size(samples, 2) ~= nAo
                error('tfp:hardware:DAQ:badShape', ...
                    'samples must be (nSamples x %d) numeric; got size [%s].', ...
                    nAo, num2str(size(samples)));
            end
            if ~isnumeric(rate) || ~isscalar(rate) || rate ~= snap.sampleRate
                error('tfp:hardware:DAQ:badRate', ...
                    'rate (%g) must equal the active session sampleRate (%g).', ...
                    double(rate), snap.sampleRate);
            end
            trigC = char(startTrigger);
            if strcmp(trigC, 'sync')
                error('tfp:hardware:DAQ:notImplemented', ...
                    'startTrigger=''sync'' is reserved for future use.');
            elseif ~strcmp(trigC, 'immediate')
                error('tfp:hardware:DAQ:badConfig', ...
                    'startTrigger must be ''immediate'' or ''sync''; got ''%s''.', trigC);
            end

            startSampleIdx = obj.currentSampleIndex();
            obj.continuousAoSamplesWritten_ = ...
                obj.continuousAoSamplesWritten_ + uint64(size(samples, 1));

            % Pair the announced stim (if any) with this waveform's onset.
            obj.events_(end+1) = struct( ...
                'onset',     double(startSampleIdx), ...
                'samples',   samples, ...
                'stim',      obj.pendingStim_, ...
                'clampMode', obj.clampState_.mode, ...
                'holdingMv', obj.clampState_.holdingMv);
            obj.pendingStim_ = [];

            obj.logEvent('queueClockedAO', struct( ...
                'startSampleIdx', startSampleIdx, ...
                'nSamples',       uint64(size(samples, 1)), ...
                'nChans',         nAo));
        end

        function idx = currentSampleIndex(obj)
            if ~obj.continuousEverStarted_
                error('tfp:hardware:DAQ:notRunning', ...
                    'currentSampleIndex called without an active continuous session.');
            end
            if obj.isRunning
                elapsed = toc(obj.continuousStartTic_);
                idx = uint64(max(0, floor(elapsed * obj.continuousCfg_.sampleRate)) + 1);
            else
                idx = obj.continuousFinalSampleCount_;
            end
        end

        function data = peekContinuousAi(obj, range)
            %peekContinuousAi Already-acquired AI from the running session.
            %   data = peekContinuousAi(obj, n)        last n samples
            %   data = peekContinuousAi(obj, [i0 i1])  that 1-based sample range
            %
            %   For LIVE DISPLAY ONLY. On real hardware this returns the actual
            %   acquired samples, identical to what stopContinuousSession will
            %   report. On this mock it re-synthesizes from the queued events, so
            %   the NOISE REALIZATION DIFFERS between a peek and the final
            %   record: the signal is right, the exact samples are not. Never
            %   analyze peeked data — the authoritative record is the one
            %   stopContinuousSession returns.
            %
            %   Mirrors the tfp.hardware.DAQ entry point of the same name (see
            %   docs/UPSTREAM_TFP_PEEK.md); this repo's copy exists so the GUI
            %   can be developed and tested mock-first.
            if ~obj.isRunning || isempty(obj.continuousCfg_)
                error('tfp:hardware:DAQ:notRunning', ...
                    'peekContinuousAi called without an active continuous session.');
            end
            snap = obj.continuousCfg_;
            nAi = numel(snap.aiChannels);
            nNow = double(obj.currentSampleIndex()) - 1;   % last acquired sample
            if nNow < 1 || nAi == 0
                data = zeros(0, nAi);
                return
            end

            if isscalar(range)
                i1 = nNow;
                i0 = max(1, nNow - double(range) + 1);
            elseif numel(range) == 2
                i0 = max(1, double(range(1)));
                i1 = min(nNow, double(range(2)));
            else
                error('tfp:hardware:DAQ:badShape', ...
                    'range must be a sample count or a [i0 i1] pair.');
            end
            if i1 < i0
                data = zeros(0, nAi);
                return
            end

            if isempty(obj.model_)
                data = randn(i1 - i0 + 1, nAi) * 0.01;
                return
            end

            % Synthesize ONLY the requested window (plus a lead-in so the
            % passive IIRs have settled), and restore the model's stream
            % afterwards. Both matter: synthesizing the whole session here made
            % a block O(n^2), and every draw from the shared stream would shift
            % the evoked responses of all later trials — the peek would change
            % the ground truth it is supposed to be observing.
            lead = round(0.2 * snap.sampleRate);
            j0 = max(1, i0 - lead);
            rngSnapshot = obj.model_.rngState();
            restore = onCleanup(@() obj.model_.setRngState(rngSnapshot));
            seg = obj.synthesizeWindow(snap, j0, i1);
            data = seg((i0 - j0 + 1):end, :);
        end

        function result = stopContinuousSession(obj)
            if ~obj.isRunning || isempty(obj.continuousCfg_)
                error('tfp:hardware:DAQ:notRunning', ...
                    'stopContinuousSession called without an active continuous session.');
            end
            snap = obj.continuousCfg_;
            elapsed = toc(obj.continuousStartTic_);
            nSamples = uint64(max(0, floor(elapsed * snap.sampleRate)));
            nS = double(nSamples);
            nAi = numel(snap.aiChannels);

            if ~isempty(obj.model_) && nAi > 0 && nS > 0
                aiData = obj.synthesizeSession(snap, nS);
            elseif nAi > 0 && nS > 0
                aiData = randn(nS, nAi) * 0.01;
            else
                aiData = zeros(nS, nAi);
            end

            nDi = numel(snap.diLines);
            diData = zeros(nS, nDi);

            lineNames = struct();
            lineNames.aiChannels = snap.aiChannels;
            lineNames.aoChannels = snap.aoChannels;
            lineNames.diLines = snap.diLines;
            lineNames.doLines = snap.doLines;
            lineNames.frameClockLine = snap.frameClockLine;

            result = struct();
            result.aiData = aiData;
            result.diData = diData;
            result.aoSamplesWritten = obj.continuousAoSamplesWritten_;
            result.nSamplesTotal = nSamples;
            result.sampleRate = snap.sampleRate;
            result.sessionStartDatetime = obj.continuousStartDatetime_;
            result.lineNames = lineNames;

            obj.continuousFinalSampleCount_ = nSamples;
            obj.isRunning = false;

            obj.logEvent('stopContinuousSession', struct( ...
                'nSamplesTotal', nSamples, ...
                'aoSamplesWritten', obj.continuousAoSamplesWritten_, ...
                'nEvents', numel(obj.events_)));
        end

        function cleanup(obj)
            obj.isRunning = false;
            obj.isInitialized = false;
            obj.queuedAo_ = [];
            obj.configuredAiChannels_ = [];
            obj.configuredAoChannels_ = [];
            obj.configuredDoLines_ = {};
            obj.configuredDiLines_ = {};
            obj.continuousCfg_ = [];
            obj.continuousEverStarted_ = false;
            obj.pendingStim_ = [];
            obj.logEvent('cleanup', []);
        end

        function entries = getLog(obj)
            %getLog Struct array of {timestamp, eventType, payload} entries.
            entries = obj.log_;
        end
    end

    methods (Access = private)
        function data = synthesizeFinite(obj, nSamples, nChans)
            %synthesizeFinite Ground-truth AI for one finite trial (DAQ volts).
            %   The per-trial finite path (configureAnalogOutput/queueAnalogOutput/
            %   start/readAnalogInput) is what the patching GUI's membrane test
            %   runs on, so it has to produce a real RC response and not just
            %   noise — otherwise patch mode cannot be developed against the mock.
            %   Same physics as synthesizeSession, minus the multi-event session
            %   reconstruction: one queued waveform, one window.
            data = randn(nSamples, nChans) * 0.01;   % no model: bare noise, as before

            if isempty(obj.model_)
                return
            end
            scaledCol = find(obj.configuredAiChannels_ == obj.aiScaledChan_, 1);
            if isempty(scaledCol)
                return   % scaled output not acquired; nothing to synthesize
            end

            % Command trace in volts. The AO line holds its last written sample
            % once the queued waveform runs out (mirrors the NI AO idle).
            cmdVolts = zeros(nSamples, 1);
            cellCol = find(obj.configuredAoChannels_ == obj.aoCellCmdChan_, 1);
            if ~isempty(obj.queuedAo_) && ~isempty(cellCol)
                w = obj.queuedAo_(:, cellCol);
                n = min(numel(w), nSamples);
                cmdVolts(1:n) = w(1:n);
                if n < nSamples
                    cmdVolts(n+1:end) = w(n);
                end
            end

            mode = obj.clampState_.mode;
            gain = obj.model_.gain;

            % The AO idles at its last written sample between sweeps, so the
            % cell arrives at the next sweep ALREADY at that level. Prepend a
            % settling segment at the carried-over level and trim it, otherwise
            % every sweep opens with a spurious capacitive transient from 0 to
            % holding -- which would swamp the trace and make the holding
            % readout (mean of the first samples) meaningless.
            nSettle = max(1, round(0.05 * obj.sampleRate));
            cmdFull = [repmat(obj.lastFiniteCmdVolts_, nSettle, 1); cmdVolts];

            cmdCell = sem.util.Units.commandDaqVoltsToCell(cmdFull, mode, gain);
            aiFull  = obj.model_.synthesizePassive(cmdCell, mode, obj.sampleRate);
            aiCell  = aiFull(nSettle + 1:end);
            aiCell  = aiCell + obj.model_.drawNoise(nSamples, mode);
            data(:, scaledCol) = sem.util.Units.scaledCellToDaqVolts(aiCell, mode, gain);

            obj.lastFiniteCmdVolts_ = cmdVolts(end);
        end

        function seg = synthesizeWindow(obj, snap, j0, j1)
            %synthesizeWindow AI over sample range [j0, j1] only (DAQ volts).
            %   Same physics as synthesizeSession over a slice, so a live peek
            %   costs O(window) rather than O(session). Callers must snapshot and
            %   restore the model's RNG around this (see peekContinuousAi).
            fs = snap.sampleRate;
            mode = obj.sessionClampMode_;
            gain = obj.model_.gain;
            nAi = numel(snap.aiChannels);
            n = j1 - j0 + 1;
            seg = randn(n, nAi) * 0.005;

            scaledCol = find(snap.aiChannels == obj.aiScaledChan_, 1);
            if isempty(scaledCol) || n <= 0
                return
            end
            cellCol = find(snap.aoChannels == obj.aoCellCmdChan_, 1);

            % Command trace across the window. Events before it only matter for
            % the level the AO line is holding when the window opens.
            cmdVolts = zeros(n, 1);
            lastVal = 0;
            cursor = j0;
            for e = 1:numel(obj.events_)
                ev = obj.events_(e);
                if isempty(cellCol)
                    w = zeros(size(ev.samples, 1), 1);
                else
                    w = ev.samples(:, cellCol);
                end
                i0e = max(1, round(ev.onset));
                i1e = i0e + numel(w) - 1;
                if i1e < j0
                    lastVal = w(end);          % entirely before: just carry the level
                    continue
                end
                if i0e > j1
                    break
                end
                a = max(i0e, j0);
                b = min(i1e, j1);
                if a > cursor
                    cmdVolts((cursor - j0 + 1):(a - j0 - 1 + 1)) = lastVal;
                end
                cmdVolts((a - j0 + 1):(b - j0 + 1)) = w((a - i0e + 1):(b - i0e + 1));
                lastVal = w(end);
                cursor = b + 1;
            end
            if cursor <= j1
                cmdVolts((cursor - j0 + 1):end) = lastVal;
            end

            cmdCell = sem.util.Units.commandDaqVoltsToCell(cmdVolts, mode, gain);
            aiCell = obj.model_.synthesizePassive(cmdCell, mode, fs);

            % Evoked responses whose window overlaps this one.
            nWin = round(0.25 * fs);
            for e = 1:numel(obj.events_)
                ev = obj.events_(e);
                if isempty(ev.stim) || ~ismember(ev.stim.kind, ...
                        {'ensemble', 'single', 'blank', 'direct'})
                    continue
                end
                i0e = max(1, round(ev.onset));
                if i0e > j1 || (i0e + nWin - 1) < j0
                    continue
                end
                clampState = struct('mode', ev.clampMode, 'holdingMv', ev.holdingMv);
                snip = obj.model_.synthesizeEvoked(ev.stim, clampState, fs, nWin);
                a = max(i0e, j0);
                b = min(i0e + nWin - 1, j1);
                aiCell((a - j0 + 1):(b - j0 + 1)) = ...
                    aiCell((a - j0 + 1):(b - j0 + 1)) + snip((a - i0e + 1):(b - i0e + 1));
            end

            aiCell = aiCell + obj.model_.drawNoise(n, mode);
            seg(:, scaledCol) = sem.util.Units.scaledCellToDaqVolts(aiCell, mode, gain);
        end

        function aiData = synthesizeSession(obj, snap, nS)
            %synthesizeSession Ground-truth AI for the whole session (DAQ volts).
            fs = snap.sampleRate;
            mode = obj.sessionClampMode_;
            gain = obj.model_.gain;
            nAi = numel(snap.aiChannels);
            aiData = randn(nS, nAi) * 0.005;   % non-ephys channels: tiny noise

            cellCol = find(snap.aoChannels == obj.aoCellCmdChan_, 1);
            scaledCol = find(snap.aiChannels == obj.aiScaledChan_, 1);
            if isempty(scaledCol)
                return   % scaled output not acquired; nothing to synthesize
            end

            % Reconstruct the cell-command AO trace: waveforms pasted at their
            % onsets, line holds its last written sample between queues.
            cmdVolts = zeros(nS, 1);
            lastVal = 0;
            cursor = 1;
            for e = 1:numel(obj.events_)
                ev = obj.events_(e);
                i0 = max(1, min(nS, round(ev.onset)));
                if i0 > cursor
                    cmdVolts(cursor:i0-1) = lastVal;
                end
                if ~isempty(cellCol)
                    w = ev.samples(:, cellCol);
                else
                    w = zeros(size(ev.samples, 1), 1);
                end
                i1 = min(nS, i0 + numel(w) - 1);
                cmdVolts(i0:i1) = w(1:(i1 - i0 + 1));
                lastVal = w(end);
                cursor = i1 + 1;
            end
            if cursor <= nS
                cmdVolts(cursor:nS) = lastVal;
            end

            cmdCell = sem.util.Units.commandDaqVoltsToCell(cmdVolts, mode, gain);
            aiCell = obj.model_.synthesizePassive(cmdCell, mode, fs);

            % Evoked responses for optogenetic stim events.
            nWin = round(0.25 * fs);
            for e = 1:numel(obj.events_)
                ev = obj.events_(e);
                if isempty(ev.stim) || ~ismember(ev.stim.kind, {'ensemble', 'single', 'blank', 'direct'})
                    continue
                end
                clampState = struct('mode', ev.clampMode, 'holdingMv', ev.holdingMv);
                snip = obj.model_.synthesizeEvoked(ev.stim, clampState, fs, nWin);
                i0 = max(1, min(nS, round(ev.onset)));
                i1 = min(nS, i0 + nWin - 1);
                aiCell(i0:i1) = aiCell(i0:i1) + snip(1:(i1 - i0 + 1));
            end

            aiCell = aiCell + obj.model_.drawNoise(nS, mode);
            aiData(:, scaledCol) = sem.util.Units.scaledCellToDaqVolts(aiCell, mode, gain);
        end

        function logEvent(obj, eventType, payload)
            entry.timestamp = datetime('now');
            entry.eventType = eventType;
            entry.payload = payload;
            obj.log_(end+1) = entry;
        end

        function requireInitialized(obj, callerName)
            if ~obj.isInitialized
                error('sem:hardware:MockEphysDAQ:notInitialized', ...
                    '%s requires initialize() to have been called first.', callerName);
            end
        end
    end
end
