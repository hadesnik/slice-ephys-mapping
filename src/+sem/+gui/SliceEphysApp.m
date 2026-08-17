classdef SliceEphysApp < handle
    %SliceEphysApp One window for the whole slice session: patch, then map.
    %
    %   Two tabs over one rig:
    %     Patch      — the live membrane test. Repeating seal-test sweeps with a
    %                  live trace, Rs/Ri/holding trends, and mode/holding
    %                  controls. This is patchclamp.gui.MainWindow's panel set
    %                  embedded in the tab, driven through
    %                  sem.hardware.PatchDaqAdapter.
    %     Experiment — run a mapping block on sem.protocol.EpisodicRunner with
    %                  live progress, seal-test trend and a working Abort.
    %
    %   One window rather than two because both modes share the amplifier, the
    %   NI board and the operator's attention, and the operator moves between
    %   them constantly during a session.
    %
    %   HARDWARE OWNERSHIP (matters on the real rig): tfp.hardware.NI6323_DAQ
    %   holds two independent NI sessions — the finite one patch mode uses and
    %   the continuous one a mapping block uses — and only one may be active at a
    %   time. The app enforces that: starting a block stops patch mode first, and
    %   patch mode cannot start while a block is running.
    %
    %   Usage:
    %       app = sem.gui.SliceEphysApp('configs/mock.yaml');
    %       app = sem.gui.SliceEphysApp(config, 'BlockPlans', plans);
    %
    %   Everything runs against the mock rig on macOS, per the repo's mock-first
    %   rule; hardwareKind in the config decides mock vs real.

    properties (SetAccess = private, GetAccess = public)
        Figure
        Config
        Dmd
        Daq
        Telegraph
        PatchAdapter
        PatchWindow       % patchclamp.gui.MainWindow, embedded
        ExperimentPanel   % sem.gui.ExperimentPanel
        BlockRunner       % sem.protocol.EpisodicRunner
        SessionDir
    end

    properties (Access = private)
        TabGroup
        PatchTab
        ExperimentTab
        IsShutdown (1,1) logical = false
        OwnsRig (1,1) logical = true
    end

    methods
        function obj = SliceEphysApp(configOrPath, options)
            arguments
                configOrPath = fullfile(sem.gui.SliceEphysApp.repoRoot(), 'configs', 'mock.yaml')
                options.SessionDir = ''
                options.BlockPlans = {}
                options.Visible (1,1) string = "on"
                options.Rig = []          % {dmd, daq} to reuse instead of building
            end

            obj.Config = sem.gui.SliceEphysApp.resolveConfig(configOrPath);

            if isempty(options.Rig)
                [obj.Dmd, obj.Daq] = sem.hardware.makeRig(obj.Config);
                obj.OwnsRig = true;
            else
                obj.Dmd = options.Rig{1};
                obj.Daq = options.Rig{2};
                obj.OwnsRig = false;
            end

            obj.SessionDir = options.SessionDir;
            if isempty(obj.SessionDir)
                dataDir = sem.util.configField( ...
                    sem.util.configField(obj.Config, 'paths', struct()), ...
                    'dataDir', tempdir());
                obj.SessionDir = fullfile(dataDir, ...
                    ['gui_session_' datestr(now, 'yyyymmdd_HHMMSS')]); %#ok<TNOW1,DATST>
            end
            if ~isfolder(obj.SessionDir)
                mkdir(obj.SessionDir);
            end

            % Mode/gain source and the bridge into the GUI's DAQ contract.
            obj.Telegraph = sem.hardware.ConfigTelegraph(obj.Config, 'VC');
            obj.PatchAdapter = sem.hardware.PatchDaqAdapter( ...
                obj.Daq, obj.Config, obj.Telegraph);

            obj.buildFigure(options.Visible);

            % --- Patch tab: the GUI panel set on the rig adapter --------------
            obj.PatchWindow = patchclamp.gui.MainWindow( ...
                'Daq', obj.PatchAdapter, ...
                'Telegraph', obj.Telegraph, ...
                'Config', sem.gui.trialConfigFromSemConfig(obj.Config), ...
                'Parent', obj.PatchTab, ...
                'Visible', options.Visible);

            % --- Experiment tab: the block engine ----------------------------
            obj.BlockRunner = sem.protocol.EpisodicRunner( ...
                obj.Dmd, obj.Daq, obj.Config, obj.SessionDir);
            % Wrap the tab in a grid so the panel fills it: a uipanel parented
            % straight to a uitab is pixel-positioned and would sit in a small
            % box at the bottom-left.
            expGrid = uigridlayout(obj.ExperimentTab, [1 1]);
            expGrid.Padding = [6 6 6 6];
            obj.ExperimentPanel = sem.gui.ExperimentPanel( ...
                expGrid, obj.BlockRunner, options.BlockPlans);

            % Board-ownership interlock.
            obj.wireInterlock();

            obj.Figure.CloseRequestFcn = @(~, ~) obj.shutdown();
        end

        function setBlockPlans(obj, plans)
            obj.ExperimentPanel.setBlockPlans(plans);
        end

        function shutdown(obj)
            if obj.IsShutdown
                return
            end
            obj.IsShutdown = true;

            try
                if ~isempty(obj.PatchWindow) && isvalid(obj.PatchWindow)
                    obj.PatchWindow.shutdown();
                end
            catch
            end
            try
                if ~isempty(obj.ExperimentPanel) && isvalid(obj.ExperimentPanel)
                    delete(obj.ExperimentPanel);
                end
            catch
            end
            try
                if obj.OwnsRig && ~isempty(obj.Daq) && isvalid(obj.Daq)
                    obj.Daq.cleanup();
                end
            catch
            end
            try
                if obj.OwnsRig && ~isempty(obj.Dmd) && isvalid(obj.Dmd) ...
                        && ismethod(obj.Dmd, 'cleanup')
                    obj.Dmd.cleanup();
                end
            catch
            end
            try
                if ~isempty(obj.Figure) && isvalid(obj.Figure)
                    delete(obj.Figure);
                end
            catch
            end
        end

        function delete(obj)
            obj.shutdown();
        end
    end

    methods (Access = private)

        function buildFigure(obj, visible)
            obj.Figure = uifigure( ...
                'Name', 'slice ephys — patch and map', ...
                'Position', [80 80 1500 950], ...
                'Visible', visible);
            obj.TabGroup = uitabgroup(obj.Figure, 'Units', 'normalized', ...
                'Position', [0 0 1 1]);
            obj.PatchTab = uitab(obj.TabGroup, 'Title', 'Patch');
            obj.ExperimentTab = uitab(obj.TabGroup, 'Title', 'Experiment');
        end

        function wireInterlock(obj)
            % A mapping block and the membrane test cannot share the board, so
            % stop patch mode before a block starts and keep it stopped until
            % the block finishes.
            addlistener(obj.ExperimentPanel, 'BlockStarted', ...
                @(~, ~) obj.onBlockStarted());
            addlistener(obj.ExperimentPanel, 'BlockFinished', ...
                @(~, ~) obj.onBlockFinished());
        end

        function onBlockStarted(obj)
            try
                obj.PatchWindow.Runner.stop();
                obj.PatchAdapter.cleanup();
            catch
                % Patch mode was not running; nothing to release.
            end
        end

        function onBlockFinished(~)
            % Patch mode stays stopped; the operator restarts it deliberately.
        end
    end

    methods (Static, Access = private)

        function root = repoRoot()
            root = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
        end

        function config = resolveConfig(configOrPath)
            if isstruct(configOrPath)
                config = configOrPath;
            else
                config = tfp.io.loadConfig(char(configOrPath));
            end
        end
    end
end
