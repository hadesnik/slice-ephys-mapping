function seg = importSegmentation(src)
%importSegmentation Load soma centroids produced by external segmentation.
%   seg = sem.targeting.importSegmentation(src)
%
%   The slice workflow images opsin+ somata with 2p/ScanImage (red-FP
%   channel) and segments them OFFLINE in external software (Cellpose,
%   Suite2p, manual clicking, ...). This importer funnels every source into
%   one struct; live delivery over msocket remains available separately via
%   tfp.io.receiveROIsFromScanImage (port 3045).
%
%   Accepted src:
%     - numeric Nx2                 : [x y] scan-field centroids, used as-is
%     - .mat file                   : containing `centroids` (Nx2), or a
%                                     single Nx2 numeric variable
%     - .csv file                   : columns x,y (header optional)
%
%   Returns seg: struct with
%     .centroids  Nx2 double, scan-field coords
%     .score      Nx1 double (NaN when the source has none)
%     .source     char, provenance (path or 'array')

if isnumeric(src)
    validateCentroids(src);
    seg = packSeg(src, nan(size(src, 1), 1), 'array');
    return
end

path = char(src);
if ~isfile(path)
    error('sem:targeting:importSegmentation:fileNotFound', ...
        'Segmentation source not found: %s.', path);
end
[~, ~, ext] = fileparts(path);
switch lower(ext)
    case '.mat'
        s = load(path);
        if isfield(s, 'centroids')
            c = s.centroids;
        else
            vars = fieldnames(s);
            numericVars = vars(cellfun(@(v) isnumeric(s.(v)) ...
                && size(s.(v), 2) == 2, vars));
            if numel(numericVars) ~= 1
                error('sem:targeting:importSegmentation:badMat', ...
                    ['%s must contain a `centroids` Nx2 variable ' ...
                     '(or exactly one Nx2 numeric variable).'], path);
            end
            c = s.(numericVars{1});
        end
        validateCentroids(c);
        score = nan(size(c, 1), 1);
        if isfield(s, 'score') && numel(s.score) == size(c, 1)
            score = double(s.score(:));
        end
        seg = packSeg(c, score, path);
    case '.csv'
        t = readmatrix(path);
        if size(t, 2) < 2
            error('sem:targeting:importSegmentation:badCsv', ...
                '%s must have at least two columns (x, y).', path);
        end
        c = t(:, 1:2);
        c = c(all(isfinite(c), 2), :);   % drops a text header row if present
        validateCentroids(c);
        seg = packSeg(c, nan(size(c, 1), 1), path);
    otherwise
        error('sem:targeting:importSegmentation:badSource', ...
            'Unsupported segmentation source: %s (need Nx2 array, .mat, or .csv).', path);
end
end

function validateCentroids(c)
if ~isnumeric(c) || ndims(c) ~= 2 || size(c, 2) ~= 2 || isempty(c) ...
        || any(~isfinite(c(:)))
    error('sem:targeting:importSegmentation:badCentroids', ...
        'centroids must be a non-empty Nx2 finite numeric array.');
end
end

function seg = packSeg(c, score, source)
seg = struct('centroids', double(c), 'score', score(:), 'source', source);
end
