classdef TrialPlotPanel < handle
    % TrialPlotPanel  Per-trial overlay of the seal-test response (first 200 ms).
    %
    % Owns a single uipanel containing one uiaxes. Each call to addTrial draws
    % a new line for the first 200 ms of the trace; older traces fade with age
    % via the 4th element of the Line Color (RGBA). At most MaxOverlay lines
    % are retained; older lines are deleted on overflow (decision A6: last 5).
    %
    % The Y-axis label flips with mode: "Current (pA)" in VC, "Voltage (mV)"
    % in IC. The X-axis is always Time (ms), 0..200.

    properties (SetAccess = private, GetAccess = public)
        Panel                                              % uipanel handle
        MaxOverlay  (1,1) uint32 = uint32(5)
    end

    properties (Access = private)
        Axes        matlab.ui.control.UIAxes
        CurrentMode string = "VC"
    end

    methods
        function obj = TrialPlotPanel(parent)
            arguments
                parent
            end

            obj.Panel = uipanel(parent, ...
                'Title', 'Seal-test response (first 200 ms)', ...
                'Units', 'normalized', ...
                'Position', [0 0 1 1]);

            obj.Axes = uiaxes(obj.Panel);
            obj.Axes.Units = 'normalized';
            obj.Axes.Position = [0.08 0.12 0.9 0.82];
            xlabel(obj.Axes, 'Time (ms)');
            obj.applyYLabel();
            xlim(obj.Axes, [0 200]);
            grid(obj.Axes, 'on');
            hold(obj.Axes, 'on');
        end

        function addTrial(obj, aiCellUnits, sampleRateHz, mode)
            arguments
                obj
                aiCellUnits   (:,1) double
                sampleRateHz  (1,1) double {mustBePositive}
                mode          (1,1) string {mustBeMember(mode, ["VC","IC"])}
            end

            obj.CurrentMode = mode;
            obj.applyYLabel();

            % First 200 ms slice.
            nWanted = max(1, round(0.2 * sampleRateHz));
            nAvail  = numel(aiCellUnits);
            nTake   = min(nWanted, nAvail);
            yseg = aiCellUnits(1:nTake);
            t = (0:(nTake-1))' / sampleRateHz * 1000;  % ms

            % Draw the new line with placeholder color; faded refresh below
            % sets the final RGBA for every line consistently.
            newLine = plot(obj.Axes, t, yseg, 'LineWidth', 1.0);

            % Cap overlay count: oldest is at index 1 (children() returns
            % newest-first in MATLAB, so we delete the last child).
            lines = obj.getLines();
            while numel(lines) > double(obj.MaxOverlay)
                delete(lines(end));   % oldest in chronological order
                lines = obj.getLines();
            end

            obj.refreshAlphas();
            % Silence "unused" warning while keeping handle accessible for
            % future debugging.
            %#ok<NASGU>
            newLine;
        end

        function clear(obj)
            lines = obj.getLines();
            for k = 1:numel(lines)
                delete(lines(k));
            end
        end

        function setMode(obj, mode)
            arguments
                obj
                mode (1,1) string {mustBeMember(mode, ["VC","IC"])}
            end
            obj.CurrentMode = mode;
            obj.applyYLabel();
        end
    end

    methods (Access = private)
        function applyYLabel(obj)
            if obj.CurrentMode == "VC"
                ylabel(obj.Axes, 'Current (pA)');
            else
                ylabel(obj.Axes, 'Voltage (mV)');
            end
        end

        function lines = getLines(obj)
            % Returns the Line children of the axes in chronological order
            % (oldest first, newest last).
            kids = obj.Axes.Children;
            mask = arrayfun(@(h) isa(h, 'matlab.graphics.chart.primitive.Line'), kids);
            lines = kids(mask);
            % Children are typically newest-first; flip so oldest is first.
            lines = flipud(lines(:));
        end

        function refreshAlphas(obj)
            % MATLAB R2023a Line.Color is stored as a 3-element RGB triple
            % (the 4-element RGBA form is accepted on assignment but the
            % alpha channel is dropped). To get a visual fade we instead
            % blend toward the axes background (white) by the alpha and
            % stash the true alpha in UserData for round-trip inspection.
            lines = obj.getLines();
            n = numel(lines);
            if n == 0
                return;
            end
            if n == 1
                alphas = 1.0;
            else
                alphas = linspace(0.2, 1.0, n);
            end
            base = [0 0.4470 0.7410];   % MATLAB default blue
            bg   = [1 1 1];             % blend target (white)
            for k = 1:n
                a = alphas(k);
                rgb = a * base + (1 - a) * bg;
                lines(k).Color = rgb;
                lines(k).UserData = struct('alpha', a);
            end
        end
    end
end
