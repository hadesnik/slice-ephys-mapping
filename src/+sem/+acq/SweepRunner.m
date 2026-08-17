classdef SweepRunner < handle
    %SweepRunner Free-running sweep loop for the acquisition GUI.
    %
    %   Start begins sweeps at a fixed ISI and keeps going until Stop. The
    %   experimenter edits stimulus parameters while it runs; each sweep reads
    %   the current parameters at its own start, so an edit takes effect on the
    %   NEXT sweep and never corrupts the one in flight. That live-editing
    %   behaviour is the whole point of the loop and is what the legacy Acq
    %   GUI's timer-driven acquire() provided.
    %
    %   ISI is ONSET-TO-ONSET, matching the legacy meaning: the delay before the
    %   next sweep is (isiSec - however long this sweep took). A sweep that
    %   overruns its ISI warns once rather than silently dropping ticks, which
    %   is what the legacy fixedRate timer did.
    %
    %   Per sweep: compose -> DAQ -> seal analysis -> QC series -> notify ->
    %   save. Listeners read the public properties off the source (notify is
    %   synchronous), the convention used elsewhere in this repo.
    %
    %   The DAQ is anything implementing the finite-trial contract
    %   (configureTrial / run / cleanup) — in practice sem.hardware.PatchDaqAdapter
    %   over the mock or the NI board.
    %
    %   See also sem.protocol.sweepWaveform, sem.hardware.PatchDaqAdapter,
    %   sem.analysis.sealAnalysis.

    events
        SweepFinished      % listener reads obj.sweepCount / lastSweep
        StateChanged       % listener reads obj.state
        AcquisitionError   % listener reads obj.lastError
    end

    properties (SetAccess = private)
        daq
        telegraph
        state = 'Idle'      % 'Idle' | 'Running' | 'Paused'
        sweepCount = 0      % sweeps acquired this session
        lastSweep = []      % struct: ai, cellCmd, led, layout, seal, mode, t
        lastError = []
        sessionDir = ''

        % QC series, one element per sweep — what the trend strips plot.
        rsMohm = []
        riMohm = []
        holding = []
        spikeCount = []
        sweepTimeMin = []
    end

    properties
        %config Live sweep configuration, re-read at the top of every sweep.
        %   Fields: durationS, isiS, testPulse, testPulseStartMs, sealTest_*,
        %   command (pulseTrain spec), led (pulseTrain spec), plus optional
        %   stepping (see stepSpec) and sealTestMode.
        config = struct()

        %stepSpec Per-sweep parameter stepping, or [] for none.
        %   struct('channel','command'|'led', 'parameter','amplitude'|
        %   'durationMs'|'nPulses'|'frequencyHz', 'delta', d)
        %   One mechanism serves both the F/I current-step family and the LED
        %   auto-update-parameter sweep; the legacy GUI had these as two
        %   separate ad-hoc code paths.
        stepSpec = []

        %saveFcn Called as saveFcn(sweepStruct) after each sweep, or [] to skip.
        saveFcn = []
    end

    properties (Access = private)
        timer_ = []
        fs_
        expStartTic_ = []
        overrunWarned_ = false
        lastHoldingMv_ = []   % holding the AO was last ramped to
    end

    methods
        function obj = SweepRunner(daq, telegraph, config, sessionDir)
            %SweepRunner Build over a finite-trial DAQ.
            if nargin < 4
                sessionDir = '';
            end
            obj.daq = daq;
            obj.telegraph = telegraph;
            obj.config = config;
            obj.sessionDir = char(sessionDir);
            obj.fs_ = sem.util.configField(config, 'sampleRateHz', 20000);
        end

        function start(obj)
            %start Begin (or resume) free-running acquisition.
            if strcmp(obj.state, 'Running')
                return   % idempotent
            end
            if isempty(obj.expStartTic_)
                obj.expStartTic_ = tic;
            end
            obj.setState('Running');
            obj.runOneSweep(true);   % first sweep runs now; the rest are timed
        end

        function acquireOne(obj)
            %acquireOne Acquire exactly one sweep now, without starting the loop.
            %   The "single sweep" action: useful for checking a stimulus before
            %   committing to a run, and the deterministic entry point for tests
            %   (start() free-runs, so it cannot be assumed to yield one sweep —
            %   a sweep longer than the ISI legitimately triggers the next one
            %   before the caller can Stop).
            if strcmp(obj.state, 'Running')
                error('sem:acq:SweepRunner:alreadyRunning', ...
                    'Stop the free-running loop before acquiring a single sweep.');
            end
            if isempty(obj.expStartTic_)
                obj.expStartTic_ = tic;
            end
            obj.runOneSweep(false);
        end

        function stop(obj)
            %stop Halt after the sweep in flight; keeps the sweep history.
            obj.cancelTimer();
            if ~strcmp(obj.state, 'Idle')
                obj.setState('Idle');
            end
        end

        function pause(obj)
            %pause Stop scheduling new sweeps, keeping the counter and history.
            if ~strcmp(obj.state, 'Running')
                return
            end
            obj.cancelTimer();
            obj.setState('Paused');
        end

        function resume(obj)
            %resume Continue after pause(), without resetting anything.
            if ~strcmp(obj.state, 'Paused')
                return
            end
            obj.setState('Running');
            obj.runOneSweep(true);
        end

        function reset(obj)
            %reset Clear the sweep history and QC series (new cell).
            if ~strcmp(obj.state, 'Idle')
                error('sem:acq:SweepRunner:notIdle', ...
                    'Stop acquisition before resetting.');
            end
            obj.sweepCount = 0;
            obj.rsMohm = [];
            obj.riMohm = [];
            obj.holding = [];
            obj.spikeCount = [];
            obj.sweepTimeMin = [];
            obj.lastSweep = [];
            obj.expStartTic_ = [];
            obj.overrunWarned_ = false;
            obj.lastHoldingMv_ = [];
        end

        function [cellCmd, led, layout] = previewSweep(obj)
            %previewSweep The waveform the NEXT sweep will deliver.
            %   The stimulus panels draw this; it is the same call the loop
            %   makes, so the preview cannot drift from what is delivered.
            [cellCmd, led, layout] = sem.protocol.sweepWaveform( ...
                obj.effectiveConfig(), obj.currentMode(), obj.fs_);
        end

        function delete(obj)
            obj.cancelTimer();
        end
    end

    methods (Access = private)

        function cfg = effectiveConfig(obj)
            %effectiveConfig The config for the next sweep, seal-mode applied.
            cfg = obj.config;
            if logical(sem.util.configField(cfg, 'sealTestMode', false))
                % Seal test: membrane test only, nothing else delivered.
                cfg.testPulse = true;
                cfg.command = struct();
                cfg.led = struct();
                cfg.durationS = sem.util.configField(cfg, 'sealTestDurationS', 0.2);
            end
        end

        function mode = currentMode(obj)
            if isempty(obj.telegraph)
                mode = char(sem.util.configField(obj.config, 'mode', 'VC'));
            else
                mode = char(obj.telegraph.getMode());
            end
        end

        function isi = effectiveIsi(obj)
            if logical(sem.util.configField(obj.config, 'sealTestMode', false))
                isi = sem.util.configField(obj.config, 'sealTestIsiS', 0.5);
            else
                isi = sem.util.configField(obj.config, 'isiS', 2.0);
            end
        end

        function runOneSweep(obj, scheduleNext)
            sweepTic = tic;
            try
                cfg = obj.effectiveConfig();
                mode = obj.currentMode();
                obj.ensureHolding(cfg, mode);
                [cellCmd, led, layout] = sem.protocol.sweepWaveform(cfg, mode, obj.fs_);

                obj.daq.configureTrial(cellCmd, led, "", obj.fs_, numel(cellCmd) / obj.fs_);
                ai = obj.daq.run();

                seal = sem.analysis.sealAnalysis(ai, mode, cfg, obj.fs_, layout);

                obj.sweepCount = obj.sweepCount + 1;
                elapsedMin = toc(obj.expStartTic_) / 60;

                obj.rsMohm(end+1)      = seal.rsMohm;
                obj.riMohm(end+1)      = seal.riMohm;
                obj.holding(end+1)     = seal.holding;
                obj.spikeCount(end+1)  = countSpikes(ai, mode);
                obj.sweepTimeMin(end+1) = elapsedMin;

                obj.lastSweep = struct( ...
                    'index',        obj.sweepCount, ...
                    'ai',           ai, ...
                    'cellCmd',      cellCmd, ...
                    'led',          led, ...
                    'layout',       layout, ...
                    'seal',         seal, ...
                    'mode',         mode, ...
                    'sampleRateHz', obj.fs_, ...
                    'timeMin',      elapsedMin);

                if ~isempty(obj.saveFcn)
                    obj.saveFcn(obj.lastSweep);
                end

                notify(obj, 'SweepFinished');

                % Step the stimulus for the next sweep, if a family is running.
                obj.applyStep();

            catch ME
                obj.lastError = ME;
                notify(obj, 'AcquisitionError');
                obj.cancelTimer();
                obj.setState('Idle');
                return
            end

            % Schedule the next sweep. Only if still Running: stop() or pause()
            % may have fired from a GUI callback during the blocking read.
            if scheduleNext && strcmp(obj.state, 'Running')
                obj.armTimer(toc(sweepTic));
            end
        end

        function ensureHolding(obj, cfg, mode)
            %ensureHolding Ramp the cell command to holding before sweeping.
            %   The AO idles at 0 before the first sweep, so without this the
            %   cell is stepped from 0 to holding in one jump: bad for the cell,
            %   and it puts a huge capacitive transient in the first sweep that
            %   corrupts the holding readout. Mirrors
            %   sem.protocol.EpisodicRunner.rampHolding, which does the same at
            %   block start.
            h = sem.util.configField(cfg, 'holdingMv', 0);
            if ~isempty(obj.lastHoldingMv_) && obj.lastHoldingMv_ == h
                return
            end
            from = 0;
            if ~isempty(obj.lastHoldingMv_)
                from = obj.lastHoldingMv_;
            end
            n = max(2, round(0.1 * obj.fs_));
            ramp = linspace(from, h, n)';
            obj.daq.configureTrial(ramp, zeros(n, 1), "", obj.fs_, n / obj.fs_);
            obj.daq.run();          % not recorded: this is a settling move
            obj.lastHoldingMv_ = h;
        end

        function applyStep(obj)
            %applyStep Advance one stimulus parameter for the next sweep.
            s = obj.stepSpec;
            if isempty(s)
                return
            end
            chan = char(sem.util.configField(s, 'channel', 'command'));
            param = char(sem.util.configField(s, 'parameter', 'amplitude'));
            delta = sem.util.configField(s, 'delta', 0);
            if delta == 0 || ~isfield(obj.config, chan)
                return
            end
            spec = obj.config.(chan);
            fieldMap = struct('amplitude', 'amplitude', ...
                'durationMs', 'pulseDurationMs', ...
                'nPulses', 'nPulses', ...
                'frequencyHz', 'frequencyHz');
            if ~isfield(fieldMap, param)
                return
            end
            f = fieldMap.(param);
            spec.(f) = sem.util.configField(spec, f, 0) + delta;
            obj.config.(chan) = spec;
        end

        function armTimer(obj, sweepElapsedS)
            obj.cancelTimer();
            % ISI is onset-to-onset: subtract the time the sweep itself took.
            gap = obj.effectiveIsi() - sweepElapsedS;
            if gap < 0 && ~obj.overrunWarned_
                warning('sem:acq:SweepRunner:isiOverrun', ...
                    ['Sweep took %.3f s, longer than the %.3f s ISI; sweeps ' ...
                     'will run back-to-back. Raise ISI or shorten the sweep.'], ...
                    sweepElapsedS, obj.effectiveIsi());
                obj.overrunWarned_ = true;
            end
            t = timer('Name', 'sem.acq.SweepRunner.isi', ...
                'Tag', 'sem.acq.SweepRunner.isi', ...
                'ExecutionMode', 'singleShot', ...
                'StartDelay', max(gap, 1e-3), ...
                'TimerFcn', @(~, ~) obj.onTimer());
            obj.timer_ = t;
            start(t);
        end

        function onTimer(obj)
            if strcmp(obj.state, 'Running')
                obj.runOneSweep(true);
            end
        end

        function cancelTimer(obj)
            if ~isempty(obj.timer_) && isvalid(obj.timer_)
                try
                    stop(obj.timer_);
                catch
                end
                delete(obj.timer_);
            end
            obj.timer_ = [];
        end

        function setState(obj, newState)
            if strcmp(obj.state, newState)
                return
            end
            obj.state = newState;
            notify(obj, 'StateChanged');
        end
    end
end

function n = countSpikes(ai, mode)
%countSpikes Upward 0 mV crossings in current clamp; NaN in voltage clamp.
%   Matches sem.analysis.quickTrialSummary's convention so the F/I curve and
%   the per-trial summary agree on what a spike is.
if ~strcmp(mode, 'IC')
    n = NaN;
    return
end
above = ai > 0;
n = nnz(diff(above) == 1);
end
