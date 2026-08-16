function targets = buildTargets(seg, calibration, config, options)
%buildTargets Convert scan-field centroids into a versioned targets struct.
%   targets = sem.targeting.buildTargets(seg, calibration, config, options)
%
%   seg: struct from sem.targeting.importSegmentation (.centroids Nx2
%   scan-field coords, .score). calibration: struct containing
%   dmdToScan_affine (3x3, DMD -> scan-field, from the DMD repo's two-step
%   calibration); centroids map to DMD pixels through its INVERSE — the same
%   composition exp_ppsf_lateral uses on the in-vivo rig.
%
%   options (struct, all optional):
%     .refImagePath     char, provenance ('' default)
%     .calibrationPath  char, provenance ('' default)
%     .patchedCellId    double (NaN default; set interactively later)
%     .layerAxisCoord   1|2, which scan-field column is the layer (depth)
%                       axis for layer assignment (default 2)
%
%   Cells whose DMD position falls outside the chip (with a spotRadiusPx
%   margin) are dropped with a warning — a stimulation disk must fit.
%
%   Errors: sem:targeting:buildTargets:noAffine when calibration lacks
%   dmdToScan_affine.

if nargin < 4 || isempty(options)
    options = struct();
end
if ~isstruct(calibration) || ~isfield(calibration, 'dmdToScan_affine')
    error('sem:targeting:buildTargets:noAffine', ...
        ['calibration must contain dmdToScan_affine (run the DMD repo''s ' ...
         'two-step calibration; see scripts/run_dmd_scan_calibration.m).']);
end
A = calibration.dmdToScan_affine;
if ~isnumeric(A) || ~isequal(size(A), [3, 3])
    error('sem:targeting:buildTargets:badAffine', ...
        'dmdToScan_affine must be a 3x3 numeric matrix.');
end

dmdCfg = sem.util.configField(config, 'dmd', struct());
nRows = sem.util.configField(dmdCfg, 'nRows', 800);
nCols = sem.util.configField(dmdCfg, 'nCols', 1280);
marginPx = sem.util.configField(dmdCfg, 'spotRadiusPx', 17);
fovCfg = sem.util.configField(config, 'fov', struct());
layerEdges = sem.util.configField(fovCfg, 'layerBoundariesUm', []);
layerAxis = sem.util.configField(options, 'layerAxisCoord', 2);

% Scan-field -> DMD: homogeneous inverse of the DMD->scan affine.
sf = seg.centroids;
n = size(sf, 1);
homog = [sf, ones(n, 1)]';
dmdH = A \ homog;                       % inv(A) * [x y 1]'
dmdH = dmdH ./ dmdH(3, :);              % defensive normalization (row-3 scale)
dmdXY = round(dmdH(1:2, :)');           % [col row]

inBounds = dmdXY(:, 1) >= 1 + marginPx & dmdXY(:, 1) <= nCols - marginPx ...
         & dmdXY(:, 2) >= 1 + marginPx & dmdXY(:, 2) <= nRows - marginPx;
if any(~inBounds)
    warning('sem:targeting:buildTargets:cellsOutsideDmd', ...
        '%d of %d cells fall outside the DMD (with a %d px margin) and were dropped.', ...
        nnz(~inBounds), n, marginPx);
end

keep = find(inBounds);
cells = struct('id', {}, 'scanfieldXY', {}, 'dmdXY', {}, 'layer', {}, ...
               'isOpsinPos', {}, 'score', {}, 'notes', {});
for i = 1:numel(keep)
    k = keep(i);
    if isempty(layerEdges)
        layer = NaN;
    else
        layer = find(sf(k, layerAxis) >= layerEdges, 1, 'last');
        if isempty(layer), layer = NaN; end
    end
    cells(i) = struct( ...
        'id',          i, ...
        'scanfieldXY', sf(k, :), ...
        'dmdXY',       dmdXY(k, :), ...
        'layer',       layer, ...
        'isOpsinPos',  true, ...
        'score',       seg.score(min(k, numel(seg.score))), ...
        'notes',       '');
end

targets = struct();
targets.version = 1;
targets.createdDatetime = datetime('now');
targets.refImagePath = char(sem.util.configField(options, 'refImagePath', ''));
targets.calibrationPath = char(sem.util.configField(options, 'calibrationPath', ''));
targets.umPerDmdPx = sem.util.configField(fovCfg, 'umPerDmdPx', NaN);
targets.patchedCellId = sem.util.configField(options, 'patchedCellId', NaN);
targets.cells = cells;
end
