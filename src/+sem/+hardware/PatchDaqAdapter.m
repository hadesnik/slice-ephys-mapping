classdef PatchDaqAdapter < patchclamp.hardware.DAQ
    %PatchDaqAdapter Run the patching GUI's DAQ contract on sem/tfp hardware.
    %
    %   The acquisition layer (sem.acq.SweepRunner) speaks a
    %   three-method finite-trial contract in CELL UNITS:
    %       configureTrial(ao0CellUnits, ao2LedVolts, aiChan, fs, durationSec)
    %       aiCellUnits = run()
    %       cleanup()
    %
    %   The rig speaks tfp.hardware.DAQ in DAQ VOLTS on numbered channels. This
    %   adapter is the only place the two meet, so it is also the only place the
    %   conversion happens (sem.util.Units, gains from config.ephys) — the same
    %   "conversion lives in exactly one place" rule the rest of the repo follows.
    %
    %   It drives the underlying DAQ's PER-TRIAL FINITE path
    %   (configureAnalogInput / configureAnalogOutput / queueAnalogOutput /
    %   start / readAnalogInput / stop), which both sem.hardware.MockEphysDAQ and
    %   tfp.hardware.NI6323_DAQ implement. That path is a self-contained finite
    %   task per trial, which is what the membrane test wants.
    %
    %   IMPORTANT (real hardware): NI6323_DAQ holds two independent NI sessions —
    %   the finite one this adapter uses, and the continuous one
    %   sem.protocol.EpisodicRunner uses for mapping blocks. Only one may be
    %   active at a time. The app is responsible for stopping patch mode before
    %   starting a block; this adapter does not police it.
    %
    %   MODE and GAIN come from the telegraph when one is supplied, which is what
    %   the GUI's DAQ contract specifies ("the backend converts using the live
    %   telegraph gain") and which keeps the conversion from drifting out of sync
    %   with what the GUI is displaying. Without a telegraph, mode is set
    %   explicitly via setClampMode and gains come from config.ephys.
    %
    %   See also sem.hardware.ConfigTelegraph, sem.util.Units.

    properties (SetAccess = private)
        daq          % the underlying tfp.hardware.DAQ
        config       % sem config struct (daq + ephys sections)
        telegraph    % patchclamp.hardware.MultiClamp, or [] if none
        clampMode = 'VC'
    end

    properties (Access = private)
        gain_
        fs_
        aoLaserChan_
        aoCellCmdChan_
        aiScaledChan_
        aiChannels_
        aoChannels_
        scaledCol_
        cellCmdCol_
        laserCol_
        queuedAo_ = []
        nSamples_ = 0
        configured_ = false
        trialMode_ = 'VC'
        trialGain_ = []
        channelsConfigured_ = false
    end

    methods
        function obj = PatchDaqAdapter(daq, config, telegraph)
            %PatchDaqAdapter Wrap a tfp DAQ in the patching GUI's DAQ contract.
            %   obj = sem.hardware.PatchDaqAdapter(daq, config)
            %   obj = sem.hardware.PatchDaqAdapter(daq, config, telegraph)
            if ~isa(daq, 'tfp.hardware.DAQ')
                error('sem:hardware:PatchDaqAdapter:badDaq', ...
                    'daq must be a tfp.hardware.DAQ; got %s.', class(daq));
            end
            if nargin < 3 || isempty(telegraph)
                telegraph = [];
            elseif ~isa(telegraph, 'patchclamp.hardware.MultiClamp')
                error('sem:hardware:PatchDaqAdapter:badTelegraph', ...
                    'telegraph must be a patchclamp.hardware.MultiClamp; got %s.', ...
                    class(telegraph));
            end
            obj.daq = daq;
            obj.config = config;
            obj.telegraph = telegraph;

            dCfg = sem.util.configField(config, 'daq', struct());
            eCfg = sem.util.configField(config, 'ephys', struct());

            obj.gain_ = sem.util.Units.gainFromConfig(eCfg);
            obj.fs_ = sem.util.configField(dCfg, 'sampleRate', 20000);
            obj.aoLaserChan_   = sem.util.configField(dCfg, 'ao_laser', 0);
            obj.aoCellCmdChan_ = sem.util.configField(dCfg, 'ao_cellCommand', 1);
            obj.aiScaledChan_  = sem.util.configField(dCfg, 'ai_scaledOutput', 0);

            % Acquire every AI channel the rig declares (the block engine does
            % the same), but drive only the two AO channels we own.
            obj.aiChannels_ = sem.util.configField(dCfg, 'analogInChannels', obj.aiScaledChan_);
            obj.aoChannels_ = [obj.aoLaserChan_, obj.aoCellCmdChan_];

            obj.scaledCol_ = find(obj.aiChannels_ == obj.aiScaledChan_, 1);
            if isempty(obj.scaledCol_)
                error('sem:hardware:PatchDaqAdapter:badChannelMap', ...
                    ['ai_scaledOutput (%d) is not in analogInChannels [%s]; the ' ...
                     'patched cell would not be acquired.'], ...
                    obj.aiScaledChan_, num2str(obj.aiChannels_));
            end
            obj.laserCol_   = 1;   % order matches obj.aoChannels_
            obj.cellCmdCol_ = 2;
        end

        function setClampMode(obj, mode)
            %setClampMode Declare the amplifier's clamp mode ('VC' or 'IC').
            %   Ignored when a telegraph is attached — that is the authority.
            modeC = char(mode);
            if ~ismember(modeC, {'VC', 'IC'})
                error('sem:hardware:PatchDaqAdapter:badMode', ...
                    'mode must be ''VC'' or ''IC''; got ''%s''.', modeC);
            end
            obj.clampMode = modeC;
        end

        function configureTrial(obj, ao0CommandCellUnits, ao2LedVolts, aiChannelName, sampleRateHz, durationSec) %#ok<INUSD>
            % aiChannelName is part of the GUI contract but the rig's AI channel
            % map comes from config.daq, so it is accepted and ignored here.
            ao0 = ao0CommandCellUnits(:);
            ao2 = ao2LedVolts(:);
            if numel(ao0) ~= numel(ao2)
                error('sem:hardware:PatchDaqAdapter:badShape', ...
                    'ao0 (%d samples) and ao2 (%d samples) must be the same length.', ...
                    numel(ao0), numel(ao2));
            end
            if isempty(ao0)
                error('sem:hardware:PatchDaqAdapter:badShape', ...
                    'the command waveform must be non-empty.');
            end

            % Latch mode and gain for this trial (telegraph wins when present),
            % so a mid-trial change cannot desync the two conversions.
            [mode, gain] = obj.latchModeAndGain();

            % Cell units -> DAQ volts. The LED/laser line has no amplifier in
            % its path, so it passes through as raw volts.
            cmdVolts = sem.util.Units.commandCellToDaqVolts(ao0, mode, gain);

            ao = zeros(numel(ao0), 2);
            ao(:, obj.laserCol_)   = ao2;
            ao(:, obj.cellCmdCol_) = cmdVolts;

            obj.queuedAo_ = ao;
            obj.nSamples_ = numel(ao0);
            obj.fs_ = sampleRateHz;
            obj.trialMode_ = mode;
            obj.trialGain_ = gain;

            obj.ensureChannelsConfigured();
            obj.daq.queueAnalogOutput(ao);
            obj.configured_ = true;
        end

        function aiSamplesCellUnits = run(obj)
            if ~obj.configured_
                error('sem:hardware:PatchDaqAdapter:notConfigured', ...
                    'configureTrial() must be called before run().');
            end
            obj.daq.start();
            raw = obj.daq.readAnalogInput(obj.nSamples_);
            obj.daq.stop();

            % DAQ volts -> cell units on the scaled-output column only, using the
            % mode/gain latched at configureTrial (contract: the gain active at
            % trial start).
            aiSamplesCellUnits = sem.util.Units.scaledDaqVoltsToCell( ...
                raw(:, obj.scaledCol_), obj.trialMode_, obj.trialGain_);
        end

        function cleanup(obj)
            % Safe to call repeatedly (GUI shutdown path calls it unconditionally).
            try
                obj.daq.stop();
            catch
                % Already stopped, or never started; nothing to release.
            end
            obj.configured_ = false;
            obj.queuedAo_ = [];
            % The next session must add its channels again; on real hardware
            % cleanup() releases the task, taking the channels with it.
            obj.channelsConfigured_ = false;
        end
    end

    methods (Access = private)
        function ensureChannelsConfigured(obj)
            %ensureChannelsConfigured Add the AI/AO channels ONCE per session.
            %   tfp.hardware.NI6323_DAQ's configureAnalogInput/Output APPEND to
            %   the legacy session (addAnalogInputChannel) and nothing removes
            %   channels short of release(). Calling them per sweep therefore
            %   doubles the channel count every sweep and the AO width stops
            %   matching the queued data within two sweeps.
            %
            %   sem.hardware.MockEphysDAQ assigns rather than appends, so the
            %   mock cannot surface this — tests/test_patch_mode_mock.m pins the
            %   call count through getLog() instead.
            if obj.channelsConfigured_
                return
            end
            dCfg = sem.util.configField(obj.config, 'daq', struct());
            aiRangeV = sem.util.configField(dCfg, 'aiRangeV', [-10, 10]);
            % The scaled output is a single-ended line on this rig class; the
            % legacy acquisition set InputType='SingleEnded' on its AI channels
            % and reading them differentially gives the wrong signal.
            singleEnded = sem.util.configField(dCfg, 'aiSingleEndedChannels', []);

            obj.daq.configureAnalogInput(obj.aiChannels_, aiRangeV, singleEnded);
            obj.daq.configureAnalogOutput(obj.aoChannels_);
            obj.channelsConfigured_ = true;
        end

        function [mode, gain] = latchModeAndGain(obj)
            %latchModeAndGain Mode/gain for this trial; telegraph is authoritative.
            if isempty(obj.telegraph)
                mode = obj.clampMode;
                gain = obj.gain_;
            else
                mode = char(obj.telegraph.getMode());
                gain = obj.telegraph.getGain();
                obj.clampMode = mode;   % keep the visible property honest
            end
        end
    end
end
