% Add the directory containing the +patchclamp package folder to the MATLAB path.
% The package folder itself must NOT be on the path; its parent directory is what
% allows `patchclamp.xxx` to resolve.
addpath(fileparts(mfilename('fullpath')));
