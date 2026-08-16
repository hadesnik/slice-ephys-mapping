function liveEphysFigure(state)
%liveEphysFigure Minimal live progress display for a running block.
%   sem.analysis.liveEphysFigure(state) updates (or creates) a small status
%   figure. state: struct with blockLabel, trialNum, nTrials, kind,
%   nMembers. Every draw is best-effort — the EpisodicRunner wraps calls in
%   try/catch so a rendering problem can never kill a block (same rule as
%   tfp.analysis.liveFigures). Disabled entirely when config.ui.liveFigure
%   is false (the default in mock/test configs; tests must never pop
%   windows).

TAG = 'semLiveEphysFigure';
fig = findobj('Type', 'figure', 'Tag', TAG);
if isempty(fig)
    fig = figure('Tag', TAG, 'Name', 'slice-ephys block progress', ...
        'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none');
    ax = axes('Parent', fig, 'Visible', 'off');
    text(0.05, 0.6, '', 'Parent', ax, 'Tag', [TAG '_text'], ...
        'FontSize', 14, 'Interpreter', 'none');
end
txt = findobj(fig, 'Tag', [TAG '_text']);
if isempty(txt)
    return
end
set(txt, 'String', sprintf('[%s]  trial %d / %d   (%s, %d members)', ...
    state.blockLabel, state.trialNum, state.nTrials, state.kind, state.nMembers));
drawnow limitrate
end
