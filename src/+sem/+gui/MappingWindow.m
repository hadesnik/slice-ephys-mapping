classdef MappingWindow < handle
    %MappingWindow DMD ensemble / PPSF mapping run, launched from AcqWindow.
    %
    %   The acquisition window is free-running: sweeps at a fixed ISI with the
    %   stimulus edited live. A mapping block is the opposite — a pre-planned,
    %   seeded, randomized sequence that must run to completion to be
    %   analyzable. Keeping it in its own window matches the legacy GUI, whose
    %   MappingGui button did the same, and keeps a protocol run from being
    %   accidentally reconfigured mid-block.
    %
    %   Shares the rig with the acquisition window. The caller stops the sweep
    %   loop before opening this, because NI6323_DAQ's finite and continuous
    %   sessions cannot both be active.
    %
    %   See also sem.gui.ExperimentPanel, sem.protocol.EpisodicRunner.

    properties (SetAccess = private, GetAccess = public)
        Figure
        Config
        Runner          % sem.protocol.EpisodicRunner
        Panel           % sem.gui.ExperimentPanel
        SessionDir
    end

    properties (Access = private)
        IsShutdown (1,1) logical = false
    end

    methods
        function obj = MappingWindow(config, options)
            arguments
                config struct
                options.Rig cell = {}
                options.SessionDir (1,:) char = ''
                options.Targets = []
                options.Telegraph = []
                options.BlockPlans cell = {}
                options.Visible (1,1) string = "on"
            end

            obj.Config = config;
            obj.SessionDir = options.SessionDir;
            if isempty(obj.SessionDir)
                obj.SessionDir = tempname();
            end
            if ~isfolder(obj.SessionDir)
                mkdir(obj.SessionDir);
            end

            if numel(options.Rig) == 2
                dmd = options.Rig{1};
                daq = options.Rig{2};
            else
                [dmd, daq] = sem.hardware.makeRig(config);
            end

            obj.Figure = uifigure('Name', 'Mapping — ensemble / PPSF block', ...
                'Position', [120 120 900 700], 'Visible', options.Visible);
            g = uigridlayout(obj.Figure, [1 1]);
            g.Padding = [6 6 6 6];

            obj.Runner = sem.protocol.EpisodicRunner(dmd, daq, config, obj.SessionDir);
            % The amplifier owns holding here too: the runner reads it and sets
            % it only to what the block asks for.
            obj.Runner.telegraph = options.Telegraph;

            plans = options.BlockPlans;
            if isempty(plans) && ~isempty(options.Targets)
                plans = obj.planFrom(options.Targets);
            end
            obj.Panel = sem.gui.ExperimentPanel(g, obj.Runner, plans);

            obj.Figure.CloseRequestFcn = @(~, ~) obj.shutdown();
        end

        function shutdown(obj)
            if obj.IsShutdown
                return
            end
            obj.IsShutdown = true;
            try, obj.Runner.abort(); catch, end
            try
                if ~isempty(obj.Panel) && isvalid(obj.Panel)
                    delete(obj.Panel);
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
        function plans = planFrom(obj, targets)
            %planFrom Build block plans from the session's targets.
            %   ensembles.mat stays the design-matrix source of truth: this
            %   generates them once, here, and hands the plans to the panel.
            plans = {};
            try
                seed = sem.util.configField( ...
                    sem.util.configField(obj.Config, 'ensemble', struct()), 'seed', 20260817);
                ens = sem.protocol.generateEnsembles(targets, obj.Config, seed);
                sem.io.saveEnsembles(ens, obj.SessionDir);
                p = sem.protocol.planBlocks(ens, targets, obj.Config);
                plans = num2cell(p);
            catch
                % No targets or an incomplete config: the panel opens empty and
                % the operator loads a plan explicitly.
            end
        end
    end
end
