classdef TrialPlotPanel < handle
    % TrialPlotPanel  Per-trial overlay of the seal-test response (first 200 ms).
    %
    % Owns a single uipanel containing one uiaxes. Each call to addTrial draws
    % a new line for the first 200 ms of the trace; older traces fade with age
    % via a blended RGB color (R2023a Line.Color drops the alpha channel, so we
    % blend toward the axes background and stash the true alpha in UserData).
    % At most MaxOverlay lines are retained; older lines are deleted on
    % overflow (decision A6: last 5).
    %
    % The Y-axis label flips with mode: "Im (pA)" in VC, "Vm (mV)" in IC. The
    % X-axis is always Time (ms), 0..200.
    %
    % Mode-change handling: when a new trial arrives in a different mode from
    % the previous one we clear the overlay. A mixed-mode overlay would be
    % ambiguous because each mode uses a different Y unit; the cleaner option
    % is to start fresh.
    %
    % Subscription to ExperimentRunner: attachRunner() addlistener's to the
    % runner's TrialFinished event. That event carries no custom EventData
    % (see ExperimentRunner.m), so onTrialFinished pulls the trial result off
    % the runner via the event's Source handle.

    properties (SetAccess = private, GetAccess = public)
        Panel                                              % uipanel handle
        MaxOverlay  (1,1) uint32 = uint32(5)
    end

    properties (Hidden, Access = ?matlab.unittest.TestCase)
        Axes        matlab.ui.control.UIAxes
    end

    properties (Access = private)
        CurrentMode string = "VC"
        RunnerListener  event.listener = event.listener.empty
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
            % from ExperimentRunner carries no custom payload, so we pull the
            % trial result off eventData.Source.lastTrialResult.
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
            if isempty(tr) || ~isstruct(tr) || ~isfield(tr, 'aiCellUnits')
                return;
            end

            obj.addTrial(tr.aiCellUnits(:), double(tr.sampleRateHz), ...
                string(tr.mode));
        end

        function reset(obj)
            % Clear all overlay lines and reset cached mode. Used when the
            % user starts a new session.
            obj.clearOverlay();
            obj.CurrentMode = "VC";
            obj.applyYLabel();
        end

        function addTrial(obj, aiCellUnits, sampleRateHz, mode)
            arguments
                obj
                aiCellUnits   (:,1) double
                sampleRateHz  (1,1) double {mustBePositive}
                mode          (1,1) string {mustBeMember(mode, ["VC","IC"])}
            end

            % Mode flip clears the overlay: mixing units on one axes is
            % visually misleading.
            if mode ~= obj.CurrentMode && obj.lineCount() > 0
                obj.clearOverlay();
            end
            obj.CurrentMode = mode;
            obj.applyYLabel();

            % First 200 ms slice.
            nWanted = max(1, round(0.2 * sampleRateHz));
            nAvail  = numel(aiCellUnits);
            nTake   = min(nWanted, nAvail);
            yseg = aiCellUnits(1:nTake);
            t = (0:(nTake-1))' / sampleRateHz * 1000;  % ms

            plot(obj.Axes, t, yseg, 'LineWidth', 1.0);

            % Cap overlay count: keep the most recent MaxOverlay lines.
            lines = obj.getLines();
            while numel(lines) > double(obj.MaxOverlay)
                delete(lines(1));   % oldest first in chronological order
                lines = obj.getLines();
            end

            obj.refreshAlphas();
        end

        function clear(obj)
            % Backward-compatible alias for reset(); retained so existing
            % callers and tests continue to work.
            obj.clearOverlay();
        end

        function setMode(obj, mode)
            arguments
                obj
                mode (1,1) string {mustBeMember(mode, ["VC","IC"])}
            end
            obj.CurrentMode = mode;
            obj.applyYLabel();
        end

        function delete(obj)
            try
                obj.detachRunner();
            catch
            end
        end
    end

    methods (Access = private)
        function applyYLabel(obj)
            if obj.CurrentMode == "VC"
                ylabel(obj.Axes, 'Im (pA)');
            else
                ylabel(obj.Axes, 'Vm (mV)');
            end
        end

        function n = lineCount(obj)
            n = numel(obj.getLines());
        end

        function clearOverlay(obj)
            lines = obj.getLines();
            for k = 1:numel(lines)
                delete(lines(k));
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
