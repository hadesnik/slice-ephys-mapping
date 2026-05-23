classdef ExperimentRunner < handle
    % ExperimentRunner  Episodic acquisition loop: Start/Stop, ITI, events.
    %
    % Wires the Round 1 components into a running session:
    %   protocol.Trial.compose  -> hardware.DAQ.configureTrial+run
    %                           -> analysis.Seal.analyzeTrial
    %                           -> storage.Hdf5Writer.appendTrial
    %                           -> notify(TrialFinished)
    %                           -> (ITI gap) -> next trial
    %
    % State machine: Idle -> Running -> Stopping -> Idle.
    %
    % Mode is latched per-trial via Telegraph.getMode() at trial start
    % (auto-mode decision A5). Stop semantics: finish the current trial,
    % then idle; never schedule the next one.
    %
    % Listeners read the latest result / state / error off the runner
    % itself; events carry no custom EventData (same pattern as
    % patchclamp.hardware.FakeTelegraph).

    events
        TrialFinished     % fires after a trial commits; listener reads obj.lastTrialResult
        StateChanged      % fires on every state transition; listener reads obj.state
        AcquisitionError  % fires when a trial throws; listener reads obj.lastError
    end

    properties (SetAccess = private, GetAccess = public)
        state            (1,1) string = "Idle"
        trialCount       (1,1) uint32 = uint32(0)
        lastTrialResult  struct       = struct()
        lastError                        = []   % MException or []
    end

    properties (Access = private)
        Daq
        Telegraph
        Writer
        Config           (1,1) struct
        ItiTimer                        = []
        AiChannelName    (1,1) string = "ai1"
    end

    methods
        function obj = ExperimentRunner(daq, telegraph, writer, config)
            arguments
                daq         (1,1) patchclamp.hardware.DAQ
                telegraph   (1,1) patchclamp.hardware.MultiClamp
                writer                                    % patchclamp.storage.Hdf5Writer or []
                config      (1,1) struct
            end

            patchclamp.config.TrialConfig.validate(config);

            obj.Daq       = daq;
            obj.Telegraph = telegraph;
            obj.Writer    = writer;
            obj.Config    = config;

            if isfield(config, "aiChannelName") && strlength(string(config.aiChannelName)) > 0
                obj.AiChannelName = string(config.aiChannelName);
            else
                obj.AiChannelName = "ai1";
            end
        end

        function start(obj)
            if obj.state == "Running"
                return;  % idempotent
            end
            if obj.state == "Stopping"
                error("patchclamp:acquisition:ExperimentRunner:badState", ...
                    "Cannot start() while state is 'Stopping'.");
            end

            obj.setState("Running");

            % Kick off the first trial immediately. Subsequent trials are
            % scheduled by runOneTrial() through the ITI timer.
            obj.runOneTrial();
        end

        function stop(obj)
            if obj.state == "Idle"
                return;
            end

            obj.cancelTimer();

            % If a trial callback is mid-execution it will see Stopping and
            % transition to Idle itself. If we are between trials (timer
            % was armed) we transition to Idle here.
            if obj.state == "Running"
                obj.setState("Stopping");
                obj.setState("Idle");
            elseif obj.state == "Stopping"
                obj.setState("Idle");
            end
        end

        function delete(obj)
            try
                obj.cancelTimer();
            catch
            end
            try
                if ~isempty(obj.Daq)
                    obj.Daq.cleanup();
                end
            catch
            end
        end
    end

    methods (Access = private)
        function runOneTrial(obj)
            try
                % A5: latch mode and snapshot gain at trial start.
                mode = obj.Telegraph.getMode();
                gainSnapshot = obj.Telegraph.getGain();

                cfg = obj.Config;
                cfg.mode = mode;  % keep struct mode consistent with the latched value

                [ao0CellUnits, ao2Volts, layout] = patchclamp.protocol.Trial.compose(cfg, mode);

                obj.Daq.configureTrial(ao0CellUnits, ao2Volts, ...
                    obj.AiChannelName, cfg.sampleRateHz, cfg.trialLengthSec);
                ai = obj.Daq.run();

                seal = patchclamp.analysis.Seal.analyzeTrial( ...
                    ai, mode, cfg.sealTest, cfg.sampleRateHz, layout);

                trialResult = struct( ...
                    'aiCellUnits',        ai, ...
                    'aoCommandCellUnits', ao0CellUnits, ...
                    'aoLedVolts',         ao2Volts, ...
                    'rsMohm',             seal.rsMohm, ...
                    'riMohm',             seal.riMohm, ...
                    'holding',            seal.holding, ...
                    'holdingUnit',        seal.holdingUnit, ...
                    'mode',               mode, ...
                    'sampleRateHz',       cfg.sampleRateHz, ...
                    'timestamp',          string(datetime("now", "Format", "yyyy-MM-dd'T'HH:mm:ss")), ...
                    'gainSnapshot',       gainSnapshot, ...
                    'trialIndex',         obj.trialCount);

                obj.lastTrialResult = trialResult;

                if ~isempty(obj.Writer)
                    obj.Writer.appendTrial(trialResult);
                end

                obj.trialCount = obj.trialCount + uint32(1);

                notify(obj, "TrialFinished");
            catch err
                obj.lastError = err;
                try
                    notify(obj, "AcquisitionError");
                catch
                end
                try
                    obj.Daq.cleanup();
                catch
                end
                obj.cancelTimer();
                obj.setState("Idle");
                return;
            end

            % Schedule the next trial, or transition to Idle if we were
            % asked to stop.
            if obj.state == "Running"
                obj.armItiTimer();
            else
                obj.setState("Idle");
            end
        end

        function armItiTimer(obj)
            obj.cancelTimer();
            iti = max(obj.Config.itiSec, 1e-3);  % timer StartDelay must be > 0
            t = timer( ...
                'Name',            'patchclamp.runner.iti', ...
                'Tag',             'patchclamp.runner.iti', ...
                'ExecutionMode',   'singleShot', ...
                'StartDelay',      iti, ...
                'TimerFcn',        @(~,~) obj.onItiTimer());
            obj.ItiTimer = t;
            start(t);
        end

        function onItiTimer(obj)
            % Timer fired: drop the reference (the timer object is about to
            % be deleted) and run the next trial -- unless stop() raced us.
            obj.cancelTimer();
            if obj.state == "Running"
                obj.runOneTrial();
            else
                obj.setState("Idle");
            end
        end

        function cancelTimer(obj)
            t = obj.ItiTimer;
            obj.ItiTimer = [];
            if isempty(t)
                return;
            end
            try
                if isvalid(t)
                    if strcmp(t.Running, 'on')
                        stop(t);
                    end
                    delete(t);
                end
            catch
            end
        end

        function setState(obj, newState)
            if obj.state == newState
                return;
            end
            obj.state = newState;
            notify(obj, "StateChanged");
        end
    end
end
