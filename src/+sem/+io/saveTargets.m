function path = saveTargets(targets, sessionDir)
%saveTargets Write the targets struct to <sessionDir>/targets.mat (v7.3).
%   path = sem.io.saveTargets(targets, sessionDir)
if ~isstruct(targets) || ~isfield(targets, 'version') || ~isfield(targets, 'cells')
    error('sem:io:saveTargets:badTargets', ...
        'targets must be a struct with version and cells fields.');
end
if ~isfolder(sessionDir)
    mkdir(sessionDir);
end
path = fullfile(char(sessionDir), 'targets.mat');
save(path, 'targets', '-v7.3');
info = dir(path);
path = fullfile(info.folder, info.name);
end
