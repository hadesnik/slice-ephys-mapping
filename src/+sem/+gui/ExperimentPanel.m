classdef ExperimentPanel < handle
    %ExperimentPanel Run and monitor a mapping block from the GUI.
    %
    %   Drives sem.protocol.EpisodicRunner: Start hands it a blockPlan, Abort
    %   asks it to stop at the next trial boundary, and the runner's events feed
    %   the progress readout, the per-trial response plot and the seal-test
    %   trend. Rs-rule violations become a modal decision instead of a warning
    %   that scrolls past unread.
    %
    %   The panel builds no blockPlan of its own — the plan struct is supplied by
    %   the host (from sem.protocol.planBlocks, or hand-built the way
    %   exp_slice_ppsf does). That keeps experiment design in the experiment
    %   layer where it is already tested.
    %
    %   Start runs runBlock synchronously on the callback's stack. That is
    %   deliberate: the runner's inter-trial pause() pumps the event queue, so
    %   Abort still fires and the UI still repaints, without restructuring the
    %   tested block loop into a timer state machine.

    properties (SetAccess = private, GetAccess = public)
        Panel
        Runner
        BlockPlans = {}
    end

    properties (Access = private, Hidden)
        Grid
        BlockDropDown
        StartButton
        AbortButton
        ProgressLabel
        StatusLabel
        LogArea
        ResponseAxes
        Listeners = event.listener.empty(1, 0)
        IsRunning (1,1) logical = false
    end

    events
        BlockStarted
        BlockFinished
    end

    methods
        function obj = ExperimentPanel(parent, runner, blockPlans)
            %ExperimentPanel Build into parent, driving runner.
            if nargin < 3
                blockPlans = {};
            end
            obj.Runner = runner;
            obj.BlockPlans = blockPlans;

            obj.Panel = uipanel(parent, 'Title', 'Mapping block');

            % One column, with nested row-grids for the two control rows. Column
            % spanning inside a uigridlayout places uiaxes unreliably here, so
            % every row owns the full width instead.
            obj.Grid = uigridlayout(obj.Panel, [6 1]);
            obj.Grid.RowHeight = {30, 34, 24, '1x', 110, 24};
            obj.Grid.ColumnWidth = {'1x'};
            obj.Grid.RowSpacing = 6;

            pickRow = uigridlayout(obj.Grid, [1 2]);
            pickRow.Layout.Row = 1;
            pickRow.ColumnWidth = {60, '1x'};
            pickRow.Padding = [0 0 0 0];
            uilabel(pickRow, 'Text', 'Block:');
            obj.BlockDropDown = uidropdown(pickRow, 'Items', obj.planLabels());

            btnRow = uigridlayout(obj.Grid, [1 3]);
            btnRow.Layout.Row = 2;
            btnRow.ColumnWidth = {130, '1x', 110};
            btnRow.Padding = [0 0 0 0];
            obj.StartButton = uibutton(btnRow, 'Text', 'Start block', ...
                'ButtonPushedFcn', @(~, ~) obj.onStart());
            uilabel(btnRow, 'Text', '');   % spacer
            obj.AbortButton = uibutton(btnRow, 'Text', 'Abort', ...
                'Enable', 'off', 'ButtonPushedFcn', @(~, ~) obj.onAbort());

            obj.ProgressLabel = uilabel(obj.Grid, 'Text', 'Idle');
            obj.ProgressLabel.Layout.Row = 3;

            % The axes lives inside a uipanel with normalized position rather
            % than directly in the grid: a uiaxes placed straight into a
            % uigridlayout row escapes the row and overdraws its neighbours.
            % This is the same nesting the patchclamp plot panels use.
            axHost = uipanel(obj.Grid, 'BorderType', 'none');
            axHost.Layout.Row = 4;
            obj.ResponseAxes = uiaxes(axHost, 'Units', 'normalized', ...
                'Position', [0 0 1 1]);
            title(obj.ResponseAxes, 'Seal test: Rs / Ri across the block');
            xlabel(obj.ResponseAxes, 'Seal test #');
            ylabel(obj.ResponseAxes, 'MOhm');
            hold(obj.ResponseAxes, 'on');

            obj.LogArea = uitextarea(obj.Grid, 'Editable', 'off', 'Value', {''});
            obj.LogArea.Layout.Row = 5;

            obj.StatusLabel = uilabel(obj.Grid, 'Text', '');
            obj.StatusLabel.Layout.Row = 6;

            obj.attachRunner();
        end

        function setBlockPlans(obj, blockPlans)
            obj.BlockPlans = blockPlans;
            obj.BlockDropDown.Items = obj.planLabels();
        end

        function delete(obj)
            for k = 1:numel(obj.Listeners)
                try
                    delete(obj.Listeners(k));
                catch
                end
            end
            obj.Listeners = event.listener.empty(1, 0);
        end
    end

    methods (Access = private)

        function labels = planLabels(obj)
            if isempty(obj.BlockPlans)
                labels = {'(no blocks loaded)'};
                return
            end
            labels = cell(1, numel(obj.BlockPlans));
            for k = 1:numel(obj.BlockPlans)
                p = obj.BlockPlans{k};
                labels{k} = sprintf('%s (%d trials)', p.label, numel(p.trials));
            end
        end

        function attachRunner(obj)
            if isempty(obj.Runner)
                return
            end
            L = event.listener.empty(1, 0);
            L(end+1) = event.listener(obj.Runner, 'BlockProgress', ...
                @(s, ~) obj.onProgress(s));
            L(end+1) = event.listener(obj.Runner, 'StateChanged', ...
                @(s, ~) obj.onStateChanged(s));
            L(end+1) = event.listener(obj.Runner, 'SealTestDone', ...
                @(s, ~) obj.onSealTest(s));
            L(end+1) = event.listener(obj.Runner, 'AcquisitionError', ...
                @(s, ~) obj.onError(s));
            obj.Listeners = L;

            % Seal-rule violations become an operator decision.
            obj.Runner.sealRuleFcn = @(info) obj.onSealRule(info);
            % Block-start operator prompts become a dialog, not a stdin read.
            obj.Runner.promptFcn = @(msg) obj.onPrompt(msg);
        end

        function onStart(obj)
            if obj.IsRunning || isempty(obj.BlockPlans)
                return
            end
            idx = find(strcmp(obj.BlockDropDown.Items, obj.BlockDropDown.Value), 1);
            if isempty(idx)
                idx = 1;
            end
            plan = obj.BlockPlans{idx};

            obj.IsRunning = true;
            obj.StartButton.Enable = 'off';
            obj.AbortButton.Enable = 'on';
            obj.appendLog(sprintf('Starting block %s (%d trials)...', ...
                plan.label, numel(plan.trials)));
            notify(obj, 'BlockStarted');
            drawnow;

            cleanupUi = onCleanup(@() obj.finishRun());
            try
                result = obj.Runner.runBlock(plan);
                if result.aborted
                    obj.appendLog(sprintf('Block aborted after %d trials. Partial block saved to %s', ...
                        obj.Runner.trialIndex, result.blockDir));
                else
                    obj.appendLog(sprintf('Block complete: %d trials, %d failed. Saved to %s', ...
                        numel(result.trials), result.nFailed, result.blockDir));
                end
            catch ME
                obj.appendLog(sprintf('Block FAILED: %s (%s)', ME.message, ME.identifier));
                obj.StatusLabel.Text = 'Block failed — see log.';
            end
            notify(obj, 'BlockFinished');
        end

        function finishRun(obj)
            obj.IsRunning = false;
            if isvalid(obj.StartButton)
                obj.StartButton.Enable = 'on';
                obj.AbortButton.Enable = 'off';
            end
        end

        function onAbort(obj)
            obj.appendLog('Abort requested; stopping at the next trial boundary.');
            obj.Runner.abort();
        end

        function onProgress(obj, runner)
            obj.ProgressLabel.Text = sprintf('Trial %d / %d', ...
                runner.trialIndex, runner.nTrials);
            drawnow limitrate;
        end

        function onStateChanged(obj, runner)
            obj.StatusLabel.Text = sprintf('Runner: %s', runner.state);
        end

        function onSealTest(obj, runner)
            s = runner.lastSealResult;
            if isempty(s)
                return
            end
            n = numel(findall(obj.ResponseAxes, 'Type', 'line')) + 1;
            plot(obj.ResponseAxes, n, s.rsMohm, 'o', 'Color', [0 0.45 0.74]);
            plot(obj.ResponseAxes, n, s.riMohm, 's', 'Color', [0.85 0.33 0.10]);
            obj.appendLog(sprintf('Seal test: Rs = %.1f MOhm, Ri = %.1f MOhm', ...
                s.rsMohm, s.riMohm));
        end

        function onError(obj, runner)
            if ~isempty(runner.lastError)
                obj.appendLog(sprintf('Trial error: %s', runner.lastError.message));
            end
        end

        function action = onSealRule(obj, info)
            % Post-hoc rule: the trials have already run, so "abort" means the
            % operator is told this block is not trustworthy.
            switch info.rule
                case 'rsAboveLimit'
                    msg = sprintf(['Rs reached %.1f MOhm (limit %.1f) in %d seal ' ...
                        'test(s) during block %s.'], info.value, info.limit, ...
                        info.count, info.blockLabel);
                otherwise
                    msg = sprintf('Rs drifted %.0f%% (limit %.0f%%) during block %s.', ...
                        info.value * 100, info.limit * 100, info.blockLabel);
            end
            obj.appendLog(['SEAL WARNING: ' msg]);
            obj.StatusLabel.Text = 'Seal quality warning — see log.';
            fig = ancestor(obj.Panel, 'figure');
            if ~isempty(fig) && isvalid(fig)
                uialert(fig, msg, 'Seal quality', 'Icon', 'warning');
            end
            action = 'continue';
        end

        function onPrompt(obj, message)
            obj.appendLog(message);
            fig = ancestor(obj.Panel, 'figure');
            if isempty(fig) || ~isvalid(fig)
                return
            end
            uiconfirm(fig, message, 'Ready?', ...
                'Options', {'Ready'}, 'DefaultOption', 1);
        end

        function appendLog(obj, line)
            if ~isvalid(obj.LogArea)
                return
            end
            v = obj.LogArea.Value;
            if numel(v) == 1 && isempty(v{1})
                v = {};
            end
            v{end+1} = char(line);
            obj.LogArea.Value = v;
            drawnow limitrate;
        end
    end
end
