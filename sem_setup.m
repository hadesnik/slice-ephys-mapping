function dmdRepo = sem_setup()
%sem_setup Path bootstrap for the slice-ephys-mapping repo.
%   dmdRepo = sem_setup() resolves the DMD control repo location, verifies it
%   is a full checkout (the tfp safety caps read docs/optics_handoff.md at
%   runtime, so src/ alone is not enough), and adds both repos' src/ folders
%   to the MATLAB path. Returns the resolved DMD repo root.
%
%   Per-machine override: create configs/dmd_repo_path_local.m (gitignored;
%   see configs/dmd_repo_path_local.m.example) returning the DMD repo root.
%   Without it the default sibling location ~/code/DMD-control-flow-software
%   is used.
%
%   This function deliberately has no tfp dependency — it is what makes tfp
%   reachable in the first place.
%
%   Errors:
%     sem:setup:dmdRepoNotFound  — resolved path is not a tfp checkout
%     sem:setup:handoffMissing   — checkout lacks docs/optics_handoff.md

thisDir = fileparts(mfilename('fullpath'));

localOverride = fullfile(thisDir, 'configs', 'dmd_repo_path_local.m');
if isfile(localOverride)
    % Run the override function without requiring it on the path.
    here = pwd;
    cleanup = onCleanup(@() cd(here));
    cd(fullfile(thisDir, 'configs'));
    dmdRepo = dmd_repo_path_local();
    clear cleanup;
    dmdRepo = char(dmdRepo);
else
    home = char(java.lang.System.getProperty('user.home'));
    dmdRepo = fullfile(home, 'code', 'DMD-control-flow-software');
end

if ~isfolder(fullfile(dmdRepo, 'src', '+tfp'))
    error('sem:setup:dmdRepoNotFound', ...
        ['DMD control repo not found at %s (no src/+tfp). Clone ' ...
         'DMD-control-flow-software there, or create ' ...
         'configs/dmd_repo_path_local.m pointing at your checkout.'], dmdRepo);
end
if ~isfile(fullfile(dmdRepo, 'docs', 'optics_handoff.md'))
    % Fail closed: tfp.hardware.DMD.assertPatternsSafe reads the handoff on
    % every pattern upload; without it no pattern can be loaded safely.
    error('sem:setup:handoffMissing', ...
        ['%s has no docs/optics_handoff.md — the tfp safety caps cannot be ' ...
         'read. Use a full DMD-repo checkout, not a copy of src/.'], dmdRepo);
end

addpath(fullfile(dmdRepo, 'src'));
addpath(fullfile(thisDir, 'src'));
end
