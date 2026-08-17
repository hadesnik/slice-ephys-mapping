function lims = paddedLimits(y, fraction)
%paddedLimits Y limits that never coincide with the data.
%   lims = sem.gui.paddedLimits(y)
%   lims = sem.gui.paddedLimits(y, fraction)
%
%   Traces in this GUI rest at a baseline for most of the sweep — 0 for a
%   stimulus, the holding current for a recording. Limits taken straight from
%   min/max put that baseline exactly on the axis edge, where the line is
%   drawn half outside the plot box and reads as missing. This always pads
%   strictly outside the data so both the baseline and the peak stay visible.
%
%   A flat trace (including all zeros) gets a real span rather than a
%   degenerate one, which MATLAB would otherwise reject or render oddly.
%
%   fraction defaults to 0.2 of the data range.

if nargin < 2 || isempty(fraction)
    fraction = 0.2;
end

y = y(isfinite(y));
if isempty(y)
    lims = [-1, 1];
    return
end

lo = min(y);
hi = max(y);
if hi > lo
    pad = fraction * (hi - lo);
else
    pad = max(abs(hi) * 0.5, 0.5);   % flat trace, including all zeros
end
lims = [lo - pad, hi + pad];
end
