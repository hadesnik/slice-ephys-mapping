function path = saveEnsembles(ens, sessionDir)
%saveEnsembles Write the ensemble set to <sessionDir>/ensembles.mat (v7.3).
%   path = sem.io.saveEnsembles(ens, sessionDir)
if ~isstruct(ens) || ~isfield(ens, 'version') || ~isfield(ens, 'X')
    error('sem:io:saveEnsembles:badEnsembles', ...
        'ens must be a struct with version and X fields.');
end
if ~isfolder(sessionDir)
    mkdir(sessionDir);
end
path = fullfile(char(sessionDir), 'ensembles.mat');
save(path, 'ens', '-v7.3');
info = dir(path);
path = fullfile(info.folder, info.name);
end
