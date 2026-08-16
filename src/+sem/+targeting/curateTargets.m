function centroids = curateTargets(refImage, centroids)
%curateTargets Manual add/remove curation of soma centroids over an image.
%   centroids = sem.targeting.curateTargets(refImage, centroids)
%
%   Interactive (rig use only; not exercised by the headless test suite).
%   Displays the 2p reference image with the current centroids overlaid:
%     left click        add a soma at the clicked position
%     right click       remove the nearest soma
%     Enter / q         finish
%   Also usable as click-only segmentation: pass centroids = zeros(0, 2).
%
%   Returns the curated Nx2 [x y] list in image-pixel coordinates.

if nargin < 2 || isempty(centroids)
    centroids = zeros(0, 2);
end

fig = figure('Name', 'curateTargets: L-click add | R-click remove | Enter done', ...
    'NumberTitle', 'off');
cleanupObj = onCleanup(@() close(fig(ishandle(fig)))); %#ok<NASGU>
imagesc(refImage);
axis image; colormap gray; hold on;
h = plot(centroids(:, 1), centroids(:, 2), 'ro', 'MarkerSize', 10, 'LineWidth', 1.5);
title(sprintf('%d cells', size(centroids, 1)));

while true
    try
        [x, y, button] = ginput(1);
    catch
        break   % figure closed
    end
    if isempty(button) || button == 'q'
        break
    end
    if button == 1
        centroids(end+1, :) = [x, y]; %#ok<AGROW>
    elseif button == 3 && ~isempty(centroids)
        d = vecnorm(centroids - [x, y], 2, 2);
        [~, k] = min(d);
        centroids(k, :) = [];
    end
    set(h, 'XData', centroids(:, 1), 'YData', centroids(:, 2));
    title(sprintf('%d cells', size(centroids, 1)));
end
end
