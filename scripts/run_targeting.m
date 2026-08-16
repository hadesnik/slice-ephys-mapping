%run_targeting Build targets.mat from an externally-segmented 2p reference.
%   Slice targeting workflow (NO camera in the loop):
%     1. Acquire a 2p reference stack in ScanImage (red-FP opsin channel).
%     2. Segment somata OFFLINE in your segmentation software (Cellpose,
%        Suite2p, manual clicking...) and export centroids in SCAN-FIELD
%        coordinates as .csv (x,y columns) or .mat (`centroids` Nx2) —
%        the same units crossRegisterScanImage used during calibration.
%     3. Point this script at that file (and optionally a mean image for
%        visual curation), run it, click the patched cell when prompted.
%
%   Alternative live path: tfp.io.receiveROIsFromScanImage (msocket, port
%   3045) delivers centroids straight from the imaging PC; pass its output
%   to sem.targeting.importSegmentation instead of a file path.
%
%   EDIT THE PARAMETERS BLOCK, then run on the rig PC:
%       run(fullfile('scripts', 'run_targeting.m'))

thisDir = fileparts(mfilename('fullpath'));
run(fullfile(thisDir, '..', 'sem_setup.m'));

% --- Parameters (edit per session) ----------------------------------------
SEG_PATH     = '';   % centroids .csv/.mat from your segmentation software
REF_IMAGE    = '';   % optional mean-image .tif for visual curation ('' = skip)
CONFIG_PATH  = fullfile(thisDir, '..', 'configs', 'slice_rig.yaml');
OUT_DIR      = fullfile(thisDir, '..', 'data', 'targeting');
% --------------------------------------------------------------------------

config = tfp.io.loadConfig(CONFIG_PATH);
if isempty(config.calibration_file) || ~isfile(config.calibration_file)
    error('run_targeting:noCalibration', ...
        ['config.calibration_file must point at a calibration containing ' ...
         'dmdToScan_affine — run scripts/run_dmd_scan_calibration.m first.']);
end
calibration = tfp.io.loadCalibration(config.calibration_file);

seg = sem.targeting.importSegmentation(SEG_PATH);
fprintf('Imported %d centroids from %s\n', size(seg.centroids, 1), seg.source);

if ~isempty(REF_IMAGE)
    refImg = imread(REF_IMAGE);
    seg.centroids = sem.targeting.curateTargets(refImg, seg.centroids);
    seg.score = nan(size(seg.centroids, 1), 1);
end

targets = sem.targeting.buildTargets(seg, calibration, config, struct( ...
    'refImagePath', REF_IMAGE, 'calibrationPath', config.calibration_file));
fprintf('%d cells mapped onto the DMD.\n', numel(targets.cells));

% Flag the patched cell (required before exp_* runs; can also be set later
% via options.patchedCellId).
idStr = input('Enter the patched cell id (or blank to set later): ', 's');
if ~isempty(strtrim(idStr))
    targets.patchedCellId = str2double(idStr);
end

path = sem.io.saveTargets(targets, OUT_DIR);
fprintf('Wrote %s\nPass this path as options.targetsPath to the experiments.\n', path);
