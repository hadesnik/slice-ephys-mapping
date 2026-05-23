classdef TrendPlotsPanel < handle
    % TrendPlotsPanel  Trial-wise trends of Rs, Ri, and holding/Vrest.
    %
    % Owns a uipanel laid out with three vertically stacked uiaxes:
    %   ax1: Series resistance (MOhm) vs trial   (VC only; IC values skipped)
    %   ax2: Input  resistance (MOhm) vs trial
    %   ax3: Holding (pA) [VC]  or  Vrest (mV) [IC]  vs trial
    %
    % Points are color-coded by mode (decision A8): blue=VC, red=IC. The Rs
    % axes title flags "VC only -- currently IC" while IC stretches contribute
    % no Rs point. The holding-axes Y-label flips on every addTrialResult so
    % the user always sees the right unit for the most recent stretch.

    properties (SetAccess = private, GetAccess = public)
        Panel
    end

    properties (Access = private)
        AxRs    matlab.ui.control.UIAxes
        AxRi    matlab.ui.control.UIAxes
        AxHold  matlab.ui.control.UIAxes
        TrialCounter (1,1) uint32 = uint32(0)
        ColorVc (1,3) double = [0.0 0.4470 0.7410]   % blue
        ColorIc (1,3) double = [0.8500 0.3250 0.0980] % red/orange
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
            if mode == "VC" && isfinite(sealStruct.rsMohm)
                plot(obj.AxRs, x, sealStruct.rsMohm, 'o', ...
                    'MarkerFaceColor', col, 'MarkerEdgeColor', col, 'MarkerSize', 6);
                title(obj.AxRs, 'Rs');
            else
                % IC stretch: visually indicate Rs is not applicable.
                title(obj.AxRs, 'Rs (VC only -- currently IC)');
            end

            % --- Ri --------------------------------------------------------------
            if isfinite(sealStruct.riMohm)
                plot(obj.AxRi, x, sealStruct.riMohm, 'o', ...
                    'MarkerFaceColor', col, 'MarkerEdgeColor', col, 'MarkerSize', 6);
            end

            % --- Holding / Vrest -------------------------------------------------
            if isfinite(sealStruct.holding)
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
            obj.clearAxesLines(obj.AxRs);
            obj.clearAxesLines(obj.AxRi);
            obj.clearAxesLines(obj.AxHold);
            obj.TrialCounter = uint32(0);
            title(obj.AxRs, 'Rs');
            ylabel(obj.AxHold, 'Holding (pA)');
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
