classdef StimulusResponsePanel < handle
    % StimulusResponsePanel  Per-trial overlay of the post-seal-test response.
    %
    % Shows the AI trace cropped to the stimulus window (i.e. the segment
    % after the seal test ends), where the optogenetic / current-injection
    % pulse train was delivered. This is the primary scientific plot.
    %
    % Crop bounds come from trialResult.layout (stimulusWindowStartIdx ..
    % stimulusWindowEndIdx) so the panel never needs to re-derive timing.
    %
    % Same faded-overlay behaviour as TrialPlotPanel: keep the most recent
    % MaxOverlay (=5, decision A6) trials; older ones blend toward the axes
    % background. Mode flip clears the overlay because the Y unit changes.
    %
    % Y-label flips with mode: "Im (pA)" in VC, "Vm (mV)" in IC.
    % X-axis is time in ms, with t=0 at stimulus-window start.

    properties (SetAccess = private, GetAccess = public)
        Panel
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
        function obj = StimulusResponsePanel(parent)
            arguments
                parent
            end

            obj.Panel = uipanel(parent, ...
                'Title', 'Stimulus response', ...
                'Units', 'normalized', ...
                'Position', [0 0 1 1]);

            obj.Axes = uiaxes(obj.Panel);
            obj.Axes.Units = 'normalized';
            obj.Axes.Position = [0.07 0.10 0.91 0.85];
            xlabel(obj.Axes, 'Time from stim onset (ms)');
            obj.applyYLabel();
            grid(obj.Axes, 'on');
            hold(obj.Axes, 'on');
        end

        function attachRunner(obj, runner)
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
            if ~isfield(tr, 'aiCellUnits') || ~isfield(tr, 'layout')
                return;
            end

            obj.addTrial(tr.aiCellUnits(:), double(tr.sampleRateHz), ...
                string(tr.mode), tr.layout);
        end

        function reset(obj)
            obj.clearOverlay();
            obj.CurrentMode = "VC";
            obj.applyYLabel();
        end

        function addTrial(obj, aiCellUnits, sampleRateHz, mode, layout)
            arguments
                obj
                aiCellUnits   (:,1) double
                sampleRateHz  (1,1) double {mustBePositive}
                mode          (1,1) string {mustBeMember(mode, ["VC","IC"])}
                layout        (1,1) struct
            end

            if mode ~= obj.CurrentMode && obj.lineCount() > 0
                obj.clearOverlay();
            end
            obj.CurrentMode = mode;
            obj.applyYLabel();

            startIdx = double(layout.stimulusWindowStartIdx);
            endIdx   = double(layout.stimulusWindowEndIdx);
            nAvail   = numel(aiCellUnits);
            startIdx = max(1, min(startIdx, nAvail));
            endIdx   = max(startIdx, min(endIdx, nAvail));

            yseg = aiCellUnits(startIdx:endIdx);
            t = (0:(numel(yseg)-1))' / sampleRateHz * 1000;  % ms from stim onset

            plot(obj.Axes, t, yseg, 'LineWidth', 1.0);

            lines = obj.getLines();
            while numel(lines) > double(obj.MaxOverlay)
                delete(lines(1));
                lines = obj.getLines();
            end

            obj.refreshAlphas();
        end

        function clear(obj)
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
            kids = obj.Axes.Children;
            mask = arrayfun(@(h) isa(h, 'matlab.graphics.chart.primitive.Line'), kids);
            lines = kids(mask);
            lines = flipud(lines(:));
        end

        function refreshAlphas(obj)
            % R2023a Line.Color drops the alpha channel on assignment; blend
            % toward the axes background to simulate a fade and stash the
            % true alpha in UserData for round-trip inspection.
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
            base = [0.85 0.33 0.10];   % MATLAB default orange — distinct from TrialPlotPanel blue
            bg   = [1 1 1];
            for k = 1:n
                a = alphas(k);
                rgb = a * base + (1 - a) * bg;
                lines(k).Color = rgb;
                lines(k).UserData = struct('alpha', a);
            end
        end
    end
end
