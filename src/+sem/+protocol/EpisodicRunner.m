classdef EpisodicRunner < handle
    %EpisodicRunner Direct-DAQ episodic engine for slice photostim blocks.
    %   Runs one clamp block at a time: a single continuous DAQ session per
    %   block, DMD patterns preloaded in chunks and advanced per trial, laser
    %   + Multiclamp-command AO queued on one hardware clock, per-trial AI
    %   sliced post-hoc from the continuous record.
    %
    %   This deliberately does NOT use tfp.trial.Sequencer: the Sequencer
    %   drives a single AO channel (we need laser + cell command together),
    %   treats powerMw as volts behind one channel, and rethrows on any trial
    %   failure — fatal mid-patch. The direct pattern follows the DMD repo's
    %   own episodic precedent (exp_ensemble_activation).
    %
    %   Holding is SOFTWARE-CONTROLLED: block start ramps the cell-command AO
    %   to the block's holding level (Commander holding assumed 0, documented
    %   in every trial's metadata.ephys), and every queued waveform's
    %   cell-command column ends at the current holding so the NI AO idle
    %   level (last written sample) keeps the cell held between trials. The
    %   laser column always ends at 0. VC<->IC MODE changes stay manual
    %   (operator prompt when opts.interactive).
    %
    %   Seal tests run at block start, every config.ephys.sealTest_everyNTrials
    %   stim trials, and at block end; they are analyzed post-hoc at finalize
    %   (Phase A: the continuous mock has no mid-session AI readback) and
    %   Rs-rule violations are surfaced as warnings in the block result.
    %
    %   Error policy: a failed trial is marked failed and the block CONTINUES;
    %   only hardware-family errors (^(sem|tfp):hardware:) abort the block.

    %   GUI integration (see also sem.gui): runBlock notifies as it goes and can
    %   be stopped mid-block. Listeners read the public properties off the source
    %   (notify is synchronous), matching how the patchclamp layer does it.
    %
    %   Stopping works without restructuring the loop because MATLAB's pause()
    %   pumps the event queue, so a GUI button callback fires during the
    %   inter-trial pause and sets the abort flag; the flag is checked at each
    %   trial boundary. An aborted block still stops the session, slices, saves
    %   and analyzes, so a partial block remains a valid, analyzable block.

    events
        TrialFinished      % listener reads obj.trialIndex / obj.lastTrialResult
        SealTestDone       % listener reads obj.lastSealResult
        BlockProgress      % listener reads obj.trialIndex / obj.nTrials
        StateChanged       % listener reads obj.state
        AcquisitionError   % listener reads obj.lastError
    end

    properties (SetAccess = private)
        dmd
        daq
        config
        sessionDir
        sessionStartTime = NaT

        state = 'Idle'        % 'Idle' | 'Running' | 'Stopping'
        trialIndex = 0        % trials completed in the current block
        nTrials = 0           % planned stim trials in the current block
        lastTrialResult = []  % most recent tfp.trial.Trial
        lastSealResult = []   % most recent seal analysis struct
        lastError = []

        %lastTrialSnippet Live view of the last trial, in CELL UNITS.
        %   Empty unless the DAQ supports peekContinuousAi. DISPLAY ONLY — the
        %   authoritative record is sliced from stopContinuousSession at block
        %   end (on the mock the peeked noise realization differs).
        lastTrialSnippet = []
    end

    properties
        %promptFcn Operator prompt, injectable so a GUI can replace stdin.
        %   Called as promptFcn(message) at block start when opts.interactive.
        %   Default prints the message and blocks on input(); a GUI supplies a
        %   uiconfirm-based handle instead.
        promptFcn = @sem.protocol.EpisodicRunner.defaultPrompt

        %sealRuleFcn Decide what to do when a seal-quality rule trips.
        %   Called as action = sealRuleFcn(info) with fields rule, value, limit,
        %   blockLabel; returns 'continue' or 'abort'. Default warns and
        %   continues, preserving the historical behavior for scripted runs.
        sealRuleFcn = @sem.protocol.EpisodicRunner.defaultSealRule
    end

    properties (Access = private)
        lastCellCmdVolts_ = 0
        gain_
        fs_
        scaledCol_ = NaN
        abortRequested_ = false
        lastBlockMode_ = 'VC'
    end

    methods
        function obj = EpisodicRunner(dmd, daq, config, sessionDir)
            obj.dmd = dmd;
            obj.daq = daq;
            obj.config = config;
            obj.sessionDir = char(sessionDir);
            if ~isfolder(obj.sessionDir)
                mkdir(obj.sessionDir);
            end
            obj.gain_ = sem.util.Units.gainFromConfig( ...
                sem.util.configField(config, 'ephys', struct()));
            obj.fs_ = sem.util.configField( ...
                sem.util.configField(config, 'daq', struct()), 'sampleRate', 20000);
            aiChans = sem.util.configField( ...
                sem.util.configField(config, 'daq', struct()), 'analogInChannels', []);
            scaledChan = sem.util.configField( ...
                sem.util.configField(config, 'daq', struct()), 'ai_scaledOutput', 0);
            col = find(aiChans == scaledChan, 1);
            if ~isempty(col)
                obj.scaledCol_ = col;
            end
        end

        function abort(obj)
            %abort Request that the running block stop at the next trial boundary.
            %   Safe to call from a GUI callback while runBlock is executing (the
            %   inter-trial pause pumps the event queue). The block still stops
            %   the session, slices, saves and analyzes what it collected.
            %   No-op when idle.
            if strcmp(obj.state, 'Running')
                obj.abortRequested_ = true;
                obj.setState('Stopping');
            end
        end

        function result = runBlock(obj, blockPlan, opts)
            %runBlock Execute one clamp block; returns trials + seal results.
            if nargin < 3 || isempty(opts)
                opts = struct();
            end
            obj.abortRequested_ = false;
            obj.trialIndex = 0;
            obj.lastError = [];
            obj.nTrials = numel(blockPlan.trials);
            obj.lastBlockMode_ = blockPlan.mode;
            obj.setState('Running');
            stateGuard = onCleanup(@() obj.setState('Idle'));
            interactive = sem.util.configField(opts, 'interactive', false);
            saveTrials = sem.util.configField(opts, 'saveTrials', true);
            liveFig = sem.util.configField( ...
                sem.util.configField(obj.config, 'ui', struct()), 'liveFigure', false);

            dCfg = obj.config.daq;
            tCfg = sem.util.configField(obj.config, 'timing', struct());
            eCfg = sem.util.configField(obj.config, 'ephys', struct());
            stimDurS = sem.util.configField(tCfg, 'stimDurS', 0.010);
            itiMeanS = sem.util.configField(tCfg, 'itiMeanS', 0.15);
            itiJitterS = sem.util.configField(tCfg, 'itiJitterS', 0.05);
            preS = sem.util.configField(tCfg, 'preS', 0.05);
            postS = sem.util.configField(tCfg, 'postS', 0.15);
            sealEveryN = sem.util.configField(eCfg, 'sealTest_everyNTrials', 100);
            chunkSize = sem.util.configField( ...
                sem.util.configField(obj.config, 'dmd', struct()), 'chunkSize', 250);

            blockDir = fullfile(obj.sessionDir, ...
                sprintf('block_%02d_%s', blockPlan.blockId, sanitizeLabel(blockPlan.label)));
            if ~isfolder(blockDir)
                mkdir(blockDir);
            end
            tfp.io.sessionLog(obj.sessionDir, 'block-start', struct( ...
                'label', blockPlan.label, 'mode', blockPlan.mode, ...
                'holdingMv', blockPlan.holdingMv, 'nTrials', numel(blockPlan.trials)));

            tfp.util.safetyChecks('arm');

            % Manual step: the amplifier owns the MODE. Holding is ours.
            if interactive
                msg = sprintf(['[%s] Set the MultiClamp Commander to %s mode now.\n' ...
                         'Holding will be commanded in software (%g mV via ' ...
                         'ao_cellCommand; Commander holding must be 0).'], ...
                    blockPlan.label, blockPlan.mode, blockPlan.holdingMv);
                obj.promptFcn(msg);
            end
            tfp.io.sessionLog(obj.sessionDir, 'clamp-state', struct( ...
                'mode', blockPlan.mode, 'holdingMv', blockPlan.holdingMv, ...
                'source', 'software'));
            sem.hardware.notifyClampState(obj.daq, ...
                struct('mode', blockPlan.mode, 'holdingMv', blockPlan.holdingMv));

            % One hardware-clocked session for the whole block. DO lines stay
            % OUT of the continuous cfg (sendDigitalPulse uses the per-trial
            % NI session; sharing a DO line across two NI tasks double-reserves
            % it — known DMD-repo gotcha).
            sessionCfg = struct( ...
                'sampleRate', obj.fs_, ...
                'aiChannels', sem.util.configField(dCfg, 'analogInChannels', []), ...
                'aiRangeV',   sem.util.configField(dCfg, 'aiRangeV', [-10, 10]), ...
                'aoChannels', [sem.util.configField(dCfg, 'ao_laser', 0), ...
                               sem.util.configField(dCfg, 'ao_cellCommand', 1)], ...
                'diLines',    {{}}, ...
                'doLines',    {{}});
            obj.daq.startContinuousSession(sessionCfg);
            obj.sessionStartTime = datetime('now');
            stopGuard = onCleanup(@() obj.ensureStopped());

            obj.markSessionBoundary(dCfg);

            % Ramp the cell command to this block's holding level.
            obj.rampHolding(blockPlan.mode, blockPlan.holdingMv);

            % Pre-jittered, seeded ITIs (recorded per trial for provenance).
            rs = RandStream('mt19937ar', 'Seed', blockPlan.shuffleSeed + 5000);
            nStimTrials = numel(blockPlan.trials);
            itis = itiMeanS + itiJitterS * (2 * rand(rs, nStimTrials, 1) - 1);

            trials = {};
            stash = {};
            nFailed = 0;
            sealSpecs = {};
            globalIdx = 0;

            % Opening seal test.
            [t, s] = obj.runSealTrial(blockPlan, globalIdx + 1, itiMeanS);
            globalIdx = globalIdx + 1;
            trials{end+1} = t; stash{end+1} = s; sealSpecs{end+1} = globalIdx; %#ok<AGROW>

            chunkStarts = 1:chunkSize:nStimTrials;
            aborted = false;
            for c = 1:numel(chunkStarts)
                if obj.abortRequested_
                    aborted = true;
                    break
                end
                idx0 = chunkStarts(c);
                idx1 = min(nStimTrials, idx0 + chunkSize - 1);
                specs = blockPlan.trials(idx0:idx1);
                patterns = obj.buildChunkPatterns(specs, blockPlan.radiusPx);
                obj.dmd.loadPatternSequence(patterns, struct( ...
                    'exposureUs', stimDurS * 1e6, 'darkTimeUs', 1000));
                obj.dmd.armSequence();

                for i = 1:numel(specs)
                    % Abort is checked at the trial boundary: the preceding
                    % pause() pumped the event queue, so a GUI Stop callback has
                    % already run and set the flag.
                    if obj.abortRequested_
                        aborted = true;
                        break
                    end
                    stimTrialNum = idx0 + i - 1;
                    globalIdx = globalIdx + 1;
                    [t, s, failed] = obj.runStimTrial(specs(i), i, globalIdx, ...
                        blockPlan, stimDurS, itis(stimTrialNum), preS, postS);
                    trials{end+1} = t; stash{end+1} = s; %#ok<AGROW>
                    nFailed = nFailed + double(failed);

                    obj.trialIndex = stimTrialNum;
                    obj.lastTrialResult = t;
                    obj.lastTrialSnippet = obj.peekTrialWindow(t, s, preS, postS);
                    notify(obj, 'TrialFinished');
                    notify(obj, 'BlockProgress');

                    if liveFig
                        obj.updateLiveFigure(blockPlan, stimTrialNum, nStimTrials, specs(i));
                    end

                    % Interleaved seal test every N stim trials.
                    if mod(stimTrialNum, sealEveryN) == 0 && stimTrialNum < nStimTrials
                        globalIdx = globalIdx + 1;
                        [t, s] = obj.runSealTrial(blockPlan, globalIdx, itiMeanS);
                        trials{end+1} = t; stash{end+1} = s; sealSpecs{end+1} = globalIdx; %#ok<AGROW>
                    end
                end
                if aborted
                    break
                end
            end
            if aborted
                tfp.io.sessionLog(obj.sessionDir, 'block-aborted', struct( ...
                    'label', blockPlan.label, 'afterStimTrials', obj.trialIndex, ...
                    'plannedStimTrials', nStimTrials));
            end

            % Closing seal test.
            globalIdx = globalIdx + 1;
            [t, s] = obj.runSealTrial(blockPlan, globalIdx, itiMeanS);
            trials{end+1} = t; stash{end+1} = s; sealSpecs{end+1} = globalIdx;

            sessionData = obj.daq.stopContinuousSession();
            clear stopGuard

            % --- Finalize: slice AI, complete, save --------------------------
            for i = 1:numel(trials)
                tr = trials{i};
                st = stash{i};
                if ~strcmp(tr.status, 'running')
                    continue   % failed trials keep their error data
                end
                [snippet, onsetIn] = sem.io.sliceSessionAi(sessionData, ...
                    tr.t_onset_daq_samples, st.offsetSample, preS, postS);
                data = struct('aiData', snippet);
                tr.markComplete(data, st.offsetSample);
                m = tr.metadata;
                m.ephys.stimOnsetSampleInSnippet = onsetIn;
                tr.metadata = m;
            end
            if saveTrials
                for i = 1:numel(trials)
                    tfp.io.saveTrial(trials{i}, blockDir);
                end
            end

            sealResults = obj.analyzeSealTrials(trials, blockPlan, eCfg);
            if ~isempty(sealResults)
                obj.lastSealResult = sealResults(end);
                notify(obj, 'SealTestDone');
            end
            obj.checkSealRules(sealResults, eCfg, blockPlan.label);

            blockMeta = struct( ...
                'label', blockPlan.label, 'blockId', blockPlan.blockId, ...
                'mode', blockPlan.mode, 'holdingMv', blockPlan.holdingMv, ...
                'shuffleSeed', blockPlan.shuffleSeed, ...
                'gains', obj.gain_, 'sampleRate', obj.fs_);
            sessionMatPath = fullfile(blockDir, 'session.mat');
            save(sessionMatPath, 'sessionData', 'blockMeta', '-v7.3');

            tfp.io.sessionLog(obj.sessionDir, 'block-end', struct( ...
                'label', blockPlan.label, 'nTrials', numel(trials), ...
                'nFailed', nFailed));

            result = struct();
            result.blockDir = blockDir;
            result.trials = trials;
            result.nFailed = nFailed;
            result.sealTests = sealResults;
            result.sessionMatPath = sessionMatPath;
            result.aborted = aborted;
        end
    end

    methods (Static)
        function defaultPrompt(message)
            %defaultPrompt Terminal operator prompt (the historical behavior).
            fprintf('\n%s\n', message);
            input('Press Enter when ready...', 's');
        end

        function action = defaultSealRule(info)
            %defaultSealRule Warn and continue, as scripted sessions always have.
            switch info.rule
                case 'rsAboveLimit'
                    warning('sem:protocol:EpisodicRunner:rsAboveLimit', ...
                        ['[%s] Rs = %.1f MOhm exceeds rsAbortMohm = %.1f in %d ' ...
                         'seal test(s).'], info.blockLabel, info.value, info.limit, ...
                        info.count);
                case 'rsDrift'
                    warning('sem:protocol:EpisodicRunner:rsDrift', ...
                        '[%s] Rs drifted %.0f%% (limit %.0f%%) from %.1f to %.1f MOhm.', ...
                        info.blockLabel, info.value * 100, info.limit * 100, ...
                        info.rsFirst, info.rsLast);
            end
            action = 'continue';
        end
    end

    methods (Access = private)
        function ensureStopped(obj)
            try
                if obj.daq.isRunning
                    obj.daq.stopContinuousSession();
                end
            catch
                % Cleanup path: never mask the original error.
            end
        end

        function markSessionBoundary(obj, dCfg)
            %markSessionBoundary Pulse do_sync so an operator scope sees block edges.
            doSync = sem.util.configField(dCfg, 'do_sync', '');
            if isempty(doSync)
                return
            end
            try
                obj.daq.configureDigitalOutput({char(doSync)});
                obj.daq.sendDigitalPulse(char(doSync), 0.005);
            catch ME
                warning('sem:protocol:EpisodicRunner:syncPulseFailed', ...
                    'do_sync pulse failed (%s); continuing without it.', ME.message);
            end
        end

        function rampHolding(obj, mode, holdingMv)
            %rampHolding ~100 ms ramp of the cell command to the block holding.
            if strcmp(mode, 'VC')
                targetVolts = sem.util.Units.commandCellToDaqVolts(holdingMv, 'VC', obj.gain_);
            else
                targetVolts = 0;   % CC blocks hold zero commanded current
            end
            nRamp = max(2, round(0.1 * obj.fs_));
            cellCol = linspace(obj.lastCellCmdVolts_, targetVolts, nRamp)';
            laserCol = zeros(nRamp, 1);
            obj.daq.queueClockedAO([laserCol, cellCol], obj.fs_, 'immediate');
            obj.lastCellCmdVolts_ = targetVolts;
            pause(0.12);
        end

        function patterns = buildChunkPatterns(obj, specs, radiusPx)
            %buildChunkPatterns Rebuild this chunk's DMD frames deterministically.
            nRows = obj.dmd.nRows;
            nCols = obj.dmd.nCols;
            patterns = false(nRows, nCols, numel(specs));
            for i = 1:numel(specs)
                if isempty(specs(i).centroids)
                    continue   % blank trial: all mirrors off
                end
                patterns(:, :, i) = tfp.patterns.fillFactorEnsemble( ...
                    obj.dmd, specs(i).centroids, radiusPx, ...
                    specs(i).fillFractions, struct('rngSeed', specs(i).patternSeed));
            end
        end

        function [tr, st, failed] = runStimTrial(obj, spec, localIdx, globalIdx, ...
                blockPlan, stimDurS, itiS, preS, postS)
            failed = false;
            tr = tfp.trial.Trial();
            tr.trialIdx = globalIdx;
            tr.sessionId = obj.sessionDir;
            tr.timestamp = datetime('now');
            tr.targetSpec = struct('cellIds', spec.memberIds, 'dmdCoords', spec.centroids);
            tr.powerMw = spec.laserVolts;   % volts until a power cal exists (see ephys meta)
            tr.duration_s = stimDurS;
            tr.preStim_s = preS;
            tr.postStim_s = postS;
            tr.pulseTrain = struct('nPulses', 1, 'interPulse_s', 0, 'pulseWidth_s', stimDurS);
            meta = struct();
            meta.ephys = sem.io.ephysMeta(blockPlan, obj.config, spec);
            meta.itiS = itiS;
            meta.extra = spec.extraMeta;
            tr.metadata = meta;
            st = struct('offsetSample', NaN);

            try
                tfp.util.safetyChecks('check');
                obj.dmd.advanceToPattern(localIdx);

                ev = struct('kind', spec.kind, 'cellIds', spec.memberIds, ...
                    'fillFractions', spec.fillFractions, ...
                    'centroids', spec.centroids, ...
                    'laserVolts', spec.laserVolts, 'durS', stimDurS);
                sem.hardware.notifyStim(obj.daq, ev);

                nStim = max(1, round(stimDurS * obj.fs_));
                laserCol = [repmat(spec.laserVolts, nStim, 1); 0];
                cellCol = repmat(obj.lastCellCmdVolts_, nStim + 1, 1);
                onset = obj.daq.queueClockedAO([laserCol, cellCol], obj.fs_, 'immediate');
                st.offsetSample = double(onset) + nStim - 1;

                tr.markRunning(onset, obj.fs_, obj.sessionStartTime);
                pause(stimDurS + itiS);
            catch ME
                failed = true;
                if ismember(tr.status, {'pending', 'running'})
                    tr.markFailed(ME);
                end
                tfp.io.sessionLog(obj.sessionDir, 'trial-failed', struct( ...
                    'trialIdx', globalIdx, 'identifier', ME.identifier, ...
                    'message', ME.message));
                obj.lastError = ME;
                notify(obj, 'AcquisitionError');
                if ~isempty(regexp(ME.identifier, '^(sem|tfp):hardware:', 'once'))
                    rethrow(ME);   % hardware faults invalidate the whole block
                end
            end
        end

        function [tr, st] = runSealTrial(obj, blockPlan, globalIdx, itiS)
            %runSealTrial Membrane-test trial: command step, laser dark, no DMD change.
            eCfg = sem.util.configField(obj.config, 'ephys', struct());
            [sealCell, layout] = sem.protocol.sealTestWaveform(eCfg, blockPlan.mode, obj.fs_);
            stepVolts = sem.util.Units.commandCellToDaqVolts(sealCell, blockPlan.mode, obj.gain_);
            cellCol = obj.lastCellCmdVolts_ + [stepVolts; 0];  % additive on holding; end at holding
            cellCol(end) = obj.lastCellCmdVolts_;
            laserCol = zeros(numel(cellCol), 1);

            spec = struct('kind', 'sealTest', 'ensembleId', NaN, 'memberIds', [], ...
                'centroids', zeros(0, 2), 'fillFractions', zeros(0, 1), ...
                'laserVolts', 0, 'patternSeed', NaN, 'extraMeta', struct('layout', layout));

            tr = tfp.trial.Trial();
            tr.trialIdx = globalIdx;
            tr.sessionId = obj.sessionDir;
            tr.timestamp = datetime('now');
            tr.targetSpec = struct('cellIds', [], 'dmdCoords', zeros(0, 2));
            tr.powerMw = 0;
            tr.duration_s = numel(cellCol) / obj.fs_;
            tr.preStim_s = 0.01;
            tr.postStim_s = 0.02;
            tr.pulseTrain = struct('nPulses', 0, 'interPulse_s', 0, 'pulseWidth_s', 0);
            meta = struct();
            meta.ephys = sem.io.ephysMeta(blockPlan, obj.config, spec);
            meta.itiS = itiS;
            meta.extra = spec.extraMeta;
            tr.metadata = meta;

            sem.hardware.notifyStim(obj.daq, struct('kind', 'sealTest'));
            onset = obj.daq.queueClockedAO([laserCol, cellCol], obj.fs_, 'immediate');
            st = struct('offsetSample', double(onset) + numel(cellCol) - 1);
            tr.markRunning(onset, obj.fs_, obj.sessionStartTime);
            pause(numel(cellCol) / obj.fs_ + itiS);
        end

        function sealResults = analyzeSealTrials(obj, trials, blockPlan, eCfg)
            sealResults = struct('trialIdx', {}, 'rsMohm', {}, 'riMohm', {}, ...
                'holding', {});
            if isnan(obj.scaledCol_)
                return
            end
            for i = 1:numel(trials)
                tr = trials{i};
                if ~strcmp(tr.status, 'complete') ...
                        || ~strcmp(tr.metadata.ephys.kind, 'sealTest')
                    continue
                end
                snippet = tr.data.aiData;
                if isempty(snippet) || size(snippet, 2) < obj.scaledCol_
                    continue
                end
                aiCell = sem.util.Units.scaledDaqVoltsToCell( ...
                    snippet(:, obj.scaledCol_), blockPlan.mode, obj.gain_);
                onsetIn = tr.metadata.ephys.stimOnsetSampleInSnippet;
                res = sem.analysis.sealAnalysis(aiCell, blockPlan.mode, eCfg, ...
                    obj.fs_, struct('sealTestStartIdx', onsetIn));
                sealResults(end+1) = struct('trialIdx', tr.trialIdx, ...
                    'rsMohm', res.rsMohm, 'riMohm', res.riMohm, ...
                    'holding', res.holding); %#ok<AGROW>
            end
        end

        function checkSealRules(obj, sealResults, eCfg, label)
            % Rules are evaluated post-hoc (Phase A has no mid-session AI
            % readback), so "abort" here means the operator is told the block is
            % not trustworthy — it cannot un-run the trials. The decision is
            % routed through sealRuleFcn so a GUI can raise a modal instead of a
            % warning that scrolls past unread.
            if isempty(sealResults)
                return
            end
            rsAbort = sem.util.configField(eCfg, 'rsAbortMohm', 30);
            driftFrac = sem.util.configField(eCfg, 'rsDriftAbortFrac', 0.25);
            rsVals = [sealResults.rsMohm];
            rsVals = rsVals(isfinite(rsVals));
            if isempty(rsVals)
                return
            end
            if any(rsVals > rsAbort)
                obj.sealRuleFcn(struct('rule', 'rsAboveLimit', ...
                    'value', max(rsVals), 'limit', rsAbort, ...
                    'count', nnz(rsVals > rsAbort), 'blockLabel', label));
            end
            if numel(rsVals) >= 2 && abs(rsVals(end) - rsVals(1)) / rsVals(1) > driftFrac
                obj.sealRuleFcn(struct('rule', 'rsDrift', ...
                    'value', abs(rsVals(end) - rsVals(1)) / rsVals(1), ...
                    'limit', driftFrac, 'rsFirst', rsVals(1), 'rsLast', rsVals(end), ...
                    'blockLabel', label));
            end
        end

        function snippet = peekTrialWindow(obj, tr, st, preS, postS)
            %peekTrialWindow This trial's response, for live display only.
            %   Uses the DAQ's peekContinuousAi when it has one. Guarded with
            %   ismethod, the same idiom sem.hardware.notifyStim uses, so the
            %   block runs unchanged on a DAQ without the entry point (the real
            %   NI6323_DAQ until the upstream change in
            %   docs/UPSTREAM_TFP_PEEK.md lands) — it just shows nothing live.
            snippet = [];
            if ~ismethod(obj.daq, 'peekContinuousAi') || isnan(obj.scaledCol_)
                return
            end
            try
                i0 = double(tr.t_onset_daq_samples) - round(preS * obj.fs_);
                i1 = st.offsetSample + round(postS * obj.fs_);
                raw = obj.daq.peekContinuousAi([max(1, i0), i1]);
                if isempty(raw) || size(raw, 2) < obj.scaledCol_
                    return
                end
                snippet = sem.util.Units.scaledDaqVoltsToCell( ...
                    raw(:, obj.scaledCol_), obj.lastBlockMode_, obj.gain_);
            catch
                % Live display is best-effort and must never break a block.
                snippet = [];
            end
        end

        function setState(obj, newState)
            if strcmp(obj.state, newState)
                return
            end
            obj.state = newState;
            notify(obj, 'StateChanged');
        end

        function updateLiveFigure(~, blockPlan, stimTrialNum, nStimTrials, spec)
            %updateLiveFigure Minimal progress display; failures never kill the run.
            try
                sem.analysis.liveEphysFigure(struct( ...
                    'blockLabel', blockPlan.label, ...
                    'trialNum', stimTrialNum, 'nTrials', nStimTrials, ...
                    'kind', spec.kind, 'nMembers', numel(spec.memberIds)));
            catch
                % Rendering is best-effort by design.
            end
        end
    end
end

% --- Local helper ---

function s = sanitizeLabel(label)
s = regexprep(char(label), '[^A-Za-z0-9]', '');
s = lower(s);
end
