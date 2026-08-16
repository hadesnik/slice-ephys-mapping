function targets = loadTargets(path)
%loadTargets Load a targets.mat written by sem.io.saveTargets.
%   targets = sem.io.loadTargets(path)
if ~isfile(path)
    error('sem:io:loadTargets:fileNotFound', 'targets file not found: %s.', char(path));
end
s = load(char(path));
if ~isfield(s, 'targets')
    error('sem:io:loadTargets:badFile', ...
        '%s does not contain a `targets` variable.', char(path));
end
targets = s.targets;
if ~isfield(targets, 'version') || ~isfield(targets, 'cells')
    error('sem:io:loadTargets:badFile', ...
        '%s targets struct is missing version/cells.', char(path));
end
end
