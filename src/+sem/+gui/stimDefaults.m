function out = stimDefaults(action, channel, spec)
%stimDefaults Persisted per-machine stimulus defaults for the acquisition GUI.
%   d = sem.gui.stimDefaults('load', channel)          -> struct, or [] if none
%   sem.gui.stimDefaults('save', channel, spec)        -> write
%   p = sem.gui.stimDefaults('path')                   -> the store's location
%
%   The "Save as defaults" buttons on the LED and cell-command panels write
%   here, so the values an experimenter converges on survive restarts instead
%   of being retyped every session.
%
%   Stored in configs/stim_defaults_local.mat, following this repo's
%   per-machine override convention: rig-specific, gitignored, and never
%   shared between machines. It is deliberately NOT the YAML — the YAML is
%   hand-edited rig truth under version control, and a GUI button that
%   rewrites it would make those two roles fight.
%
%   channel is 'led' or 'command'. spec is a sem.protocol.pulseTrain spec.

if nargin < 2
    channel = '';
end

storePath = fullfile(repoRoot(), 'configs', 'stim_defaults_local.mat');

switch lower(char(action))
    case 'path'
        out = storePath;

    case 'load'
        out = [];
        if ~isfile(storePath)
            return
        end
        try
            s = load(storePath);
        catch
            return   % unreadable or from an older layout: fall back to built-ins
        end
        if isfield(s, 'defaults') && isfield(s.defaults, channel)
            out = s.defaults.(channel);
        end

    case 'save'
        if nargin < 3 || ~isstruct(spec)
            error('sem:gui:stimDefaults:badSpec', 'spec must be a struct.');
        end
        defaults = struct();
        if isfile(storePath)
            try
                prev = load(storePath);
                if isfield(prev, 'defaults')
                    defaults = prev.defaults;
                end
            catch
                % Corrupt store: start a fresh one rather than refusing to save.
            end
        end
        defaults.(channel) = charifyFields(spec);
        cfgDir = fileparts(storePath);
        if ~isfolder(cfgDir)
            mkdir(cfgDir);
        end
        save(storePath, 'defaults');
        out = storePath;

    otherwise
        error('sem:gui:stimDefaults:badAction', ...
            'action must be ''load'', ''save'' or ''path''; got ''%s''.', char(action));
end
end

function r = repoRoot()
r = fileparts(fileparts(fileparts(fileparts(mfilename('fullpath')))));
end

function s = charifyFields(s)
%charifyFields Keep the store free of string/datetime, per the repo rule.
f = fieldnames(s);
for k = 1:numel(f)
    v = s.(f{k});
    if isstring(v)
        s.(f{k}) = char(v);
    end
end
end
