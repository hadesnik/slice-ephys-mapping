function targets = mockTargets(config)
%mockTargets Fabricate a targets struct for mock sessions.
%   targets = sem.targeting.mockTargets(config) lays config.groundTruth.nCells
%   somata on a jittered grid across the config.fov FOV (widthUm x heightUm,
%   long axis = cortical depth), converts to DMD pixels around the chip
%   center via fov.umPerDmdPx, and returns the same versioned struct
%   sem.targeting.buildTargets produces for real sessions — so the whole
%   downstream pipeline (ensembles, patterns, saving, Python) exercises the
%   real file format. Seeded from config.groundTruth.seed.

gtCfg = sem.util.configField(config, 'groundTruth', struct());
fovCfg = sem.util.configField(config, 'fov', struct());
nCells = sem.util.configField(gtCfg, 'nCells', 25);
seed = sem.util.configField(gtCfg, 'seed', 42);
rs = RandStream('mt19937ar', 'Seed', seed + 1);   % offset: independent of weight draws

wUm = sem.util.configField(fovCfg, 'widthUm', 300);
hUm = sem.util.configField(fovCfg, 'heightUm', 600);
umPerPx = sem.util.configField(fovCfg, 'umPerDmdPx', 0.6);
layerEdges = sem.util.configField(fovCfg, 'layerBoundariesUm', [0, hUm]);

nRows = sem.util.configField(sem.util.configField(config, 'dmd', struct()), 'nRows', 800);
nCols = sem.util.configField(sem.util.configField(config, 'dmd', struct()), 'nCols', 1280);

% Jittered grid filling the FOV (x across width, y down the layer axis).
nGridY = ceil(sqrt(nCells * hUm / wUm));
nGridX = ceil(nCells / nGridY);
[gx, gy] = meshgrid( ...
    linspace(0.12, 0.88, nGridX), ...
    linspace(0.06, 0.94, nGridY));
xy = [gx(:), gy(:)];
xy = xy(1:nCells, :);
xUm = xy(:, 1) * wUm + 8 * randn(rs, nCells, 1);
yUm = xy(:, 2) * hUm + 8 * randn(rs, nCells, 1);
xUm = min(max(xUm, 5), wUm - 5);
yUm = min(max(yUm, 5), hUm - 5);

% DMD coords: FOV centered on the chip. Long (layer) axis along DMD cols.
colPx = round(nCols / 2 + (yUm - hUm / 2) / umPerPx);
rowPx = round(nRows / 2 + (xUm - wUm / 2) / umPerPx);

cells = struct('id', {}, 'scanfieldXY', {}, 'dmdXY', {}, 'layer', {}, ...
               'isOpsinPos', {}, 'score', {}, 'notes', {});
for k = 1:nCells
    layer = find(yUm(k) >= layerEdges, 1, 'last');
    cells(k) = struct( ...
        'id',          k, ...
        'scanfieldXY', [xUm(k), yUm(k)], ...
        'dmdXY',       [colPx(k), rowPx(k)], ...
        'layer',       layer, ...
        'isOpsinPos',  true, ...   % opsin- identity lives in the ground-truth model
        'score',       1.0, ...
        'notes',       '');
end

targets = struct();
targets.version = 1;
targets.createdDatetime = datetime('now');
targets.refImagePath = '';
targets.calibrationPath = '';
targets.umPerDmdPx = umPerPx;
targets.patchedCellId = NaN;
targets.cells = cells;
end
