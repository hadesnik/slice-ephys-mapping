function path = saveGroundTruth(gt, sessionDir)
%saveGroundTruth Write the mock ground truth to <sessionDir>/ground_truth.mat.
%   path = sem.io.saveGroundTruth(gt, sessionDir)
%   gt comes from sem.sim.SliceNetworkModel.exportGroundTruth. Mock sessions
%   only — its presence is how the Python roundtrip test recognizes a
%   validatable session.
if ~isstruct(gt) || ~isfield(gt, 'W_E_eff')
    error('sem:io:saveGroundTruth:badGroundTruth', ...
        'gt must come from SliceNetworkModel.exportGroundTruth.');
end
if ~isfolder(sessionDir)
    mkdir(sessionDir);
end
path = fullfile(char(sessionDir), 'ground_truth.mat');
save(path, 'gt', '-v7.3');
info = dir(path);
path = fullfile(info.folder, info.name);
end
