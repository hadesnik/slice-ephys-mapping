function ens = loadEnsembles(path)
%loadEnsembles Load an ensembles.mat written by sem.io.saveEnsembles.
%   ens = sem.io.loadEnsembles(path)
if ~isfile(path)
    error('sem:io:loadEnsembles:fileNotFound', 'ensembles file not found: %s.', char(path));
end
s = load(char(path));
if ~isfield(s, 'ens')
    error('sem:io:loadEnsembles:badFile', ...
        '%s does not contain an `ens` variable.', char(path));
end
ens = s.ens;
if ~isfield(ens, 'version') || ~isfield(ens, 'X')
    error('sem:io:loadEnsembles:badFile', ...
        '%s ensemble struct is missing version/X.', char(path));
end
end
