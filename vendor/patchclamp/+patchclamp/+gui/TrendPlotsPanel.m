classdef TrendPlotsPanel < handle
    % TrendPlotsPanel  Trial-wise trends of Rs, Ri, and holding/Vrest.
    %
    % Owns a uipanel laid out with three vertically stacked uiaxes:
    %   ax1: Series resistance (MOhm) vs trial   (VC only; IC values skipped)
    %   ax2: Input  resistance (MOhm) vs trial
    %   ax3: Holding (pA) [VC]  or  Vrest (mV) [IC]  vs trial
    %
    % Points are color-coded by mode (decision A8/Q8): blue = VC, red = IC.
    % The Rs axes title flags "VC only -- currently IC" while IC trials
    % contribute no Rs point; the gap is visible. The holding-axes Y-label
    % flips on every addTrialResult so the user always sees the right unit
    % for the most recent trial.
    %
    % Subscription to ExperimentRunner: attachRunner() addlistener's to the
    % runner's TrialFinished event. That event carries no custom EventData
    % (see ExperimentRunner.m), so onTrialFinished pulls the trial result
    % off the runner via the event's Source handle.

    properties (SetAccess = private, GetAccess = public)
        Panel
    end

    properties (Hidden, Access = ?matlab.unittest.TestCase)
        AxRs    matlab.ui.control.UIAxes
        AxRi    matlab.ui.control.UIAxes
        AxHold  matlab.ui.control.UIAxes
    end

    properties (Access = private)
        TrialCounter (1,1) uint32 = uint32(0)
        ColorVc (1,3) double = [0.0 0.4470 0.7410]   % blue
        ColorIc (1,3) double = [0.8500 0.3250 0.0980] % red/orange
        RunnerListener  event.listener = event.listener.empty
    end

    methods
        function obj = TrendPlotsPanel(parent)
            arguments
                parent
            end

            obj.Panel = uipanel(parent, ...
                'Title', 'Trial-wise trends', ...
                'Units', 'normalized', ...
                'Position', [0 0 1 1]);

            % Vertical layout via uigridlayout.
            grid = uigridlayout(obj.Panel, [3 1]);
            grid.RowHeight = {'1x','1x','1x'};
            grid.ColumnWidth = {'1x'};

            obj.AxRs   = uiaxes(grid);
            obj.AxRi   = uiaxes(grid);
            obj.AxHold = uiaxes(grid);

            obj.configureAxes(obj.AxRs,   'Trial #', 'Series resistance (MOhm)', 'Rs');
            obj.configureAxes(obj.AxRi,   'Trial #', 'Input resistance (MOhm)',  'Ri');
            obj.configureAxes(obj.AxHold, 'Trial #', 'Holding (pA)',             'Holding / Vrest');

            hold(obj.AxRs, 'on');
            hold(obj.AxRi, 'on');
            hold(obj.AxHold, 'on');
        end

        function attachRunner(obj, runner)
            % Subscribe to runner.TrialFinished. TrialFinished carries no
            % custom EventData; we read runner.lastTrialResult on each fire.
            arguments
                obj
                runner (1,1) handle
            end
            obj.detachRunner();
            obj.RunnerListener = addlistener(runner, "TrialFinished", ...
                @(s,e) obj.onTrialFinished(e));
        end

        function detachRunner(obj)
            if ~isempty(obj.RunnerListener) && isvalid(obj.RunnerListener)
                delete(obj.RunnerListener);
            end
            obj.RunnerListener = event.listener.empty;
        end

        function onTrialFinished(obj, eventData)
            % Single callback used by attachRunner. The TrialFinished event
            % from ExperimentRunner carries no custom payload, so we pull
            % the trial result off eventData.Source.lastTrialResult.
            arguments
                obj
                eventData
            end
            try
                src = eventData.Source;
                tr  = src.lastTrialResult;
            catch
                return;
            end
            if isempty(tr) || ~isstruct(tr)
                return;
            end
            obj.addTrialResult(tr);
        end

        function reset(obj)
            % Clear all trend points and reset the trial counter. Used when
            % the user starts a new session.
            obj.clearAxesLines(obj.AxRs);
            obj.clearAxesLines(obj.AxRi);
            obj.clearAxesLines(obj.AxHold);
            obj.TrialCounter = uint32(0);
            title(obj.AxRs, 'Rs');
            ylabel(obj.AxHold, 'Holding (pA)');
        end

        function addTrialResult(obj, sealStruct)
            arguments
                obj
                sealStruct struct
            end

            obj.TrialCounter = obj.TrialCounter + uint32(1);
            x = double(obj.TrialCounter);

            mode = string(sealStruct.mode);
            if mode == "VC"
                col = obj.ColorVc;
            else
                col = obj.ColorIc;
            end

            % --- Rs (VC only) ----------------------------------------------------
            if mode == "VC" && isfield(sealStruct, 'rsMohm') && isfinite(sealStruct.rsMohm)
                plot(obj.AxRs, x, sealStruct.rsMohm, 'o', ...
                    'MarkerFaceColor', col, 'MarkerEdgeColor', col, 'MarkerSize', 6);
                title(obj.AxRs, 'Rs');
            else
                % IC stretch: visually indicate Rs is not applicable.
                title(obj.AxRs, 'Rs (N/A in IC)');
            end

            % --- Ri --------------------------------------------------------------
            if isfield(sealStruct, 'riMohm') && isfinite(sealStruct.riMohm)
                plot(obj.AxRi, x, sealStruct.riMohm, 'o', ...
                    'MarkerFaceColor', col, 'MarkerEdgeColor', col, 'MarkerSize', 6);
            end

            % --- Holding / Vrest -------------------------------------------------
            if isfield(sealStruct, 'holding') && isfinite(sealStruct.holding)
                plot(obj.AxHold, x, sealStruct.holding, 'o', ...
                    'MarkerFaceColor', col, 'MarkerEdgeColor', col, 'MarkerSize', 6);
            end
            if mode == "VC"
                ylabel(obj.AxHold, 'Holding (pA)');
            else
                ylabel(obj.AxHold, 'Vrest (mV)');
            end
        end

        function clear(obj)
            % Backward-compatible alias for reset(); retained so existing
            % callers and tests continue to work.
            obj.reset();
        end

        function delete(obj)
            try
                obj.detachRunner();
            catch
            end
        end
    end

    methods (Access = private)
        function configureAxes(~, ax, xlab, ylab, ttl)
            xlabel(ax, xlab);
            ylabel(ax, ylab);
            title(ax, ttl);
            grid(ax, 'on');
        end

        function clearAxesLines(~, ax)
            kids = ax.Children;
            for k = 1:numel(kids)
                if isa(kids(k), 'matlab.graphics.chart.primitive.Line') || ...
                   isa(kids(k), 'matlab.graphics.chart.primitive.Scatter')
                    delete(kids(k));
                end
            end
        end
    end
end
