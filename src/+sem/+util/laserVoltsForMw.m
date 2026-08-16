function volts = laserVoltsForMw(powerMw, calibration, config)
%laserVoltsForMw Convert a target power at sample (mW) to the laser AO voltage.
%   volts = sem.util.laserVoltsForMw(powerMw, calibration, config)
%
%   Uses calibration.powerCurve when present (from
%   tfp.calibration.powerMeterSweep: fields .voltage [V] and .powerAtSample
%   [mW], monotone increasing), interpolating linearly and clamping to the
%   measured range. Without a power curve the identity fallback volts =
%   powerMw is used — the same convention the DMD repo's Sequencer applies
%   while its TODO C2 is open — and a one-shot warning is emitted per session.
%
%   The result is clamped to [0, config.laser.ao_voltage_max] (default 5 V).
%
%   See also sem.util.mwForLaserVolts.

if ~isnumeric(powerMw) || any(~isfinite(powerMw(:))) || any(powerMw(:) < 0)
    error('sem:util:laserVoltsForMw:badPower', ...
        'powerMw must be finite and non-negative.');
end

maxV = 5.0;
if nargin >= 3 && isstruct(config) && isfield(config, 'laser')
    maxV = sem.util.configField(config.laser, 'ao_voltage_max', 5.0);
end

curve = [];
if nargin >= 2 && isstruct(calibration) && isfield(calibration, 'powerCurve') ...
        && isstruct(calibration.powerCurve) ...
        && isfield(calibration.powerCurve, 'voltage') ...
        && isfield(calibration.powerCurve, 'powerAtSample')
    curve = calibration.powerCurve;
end

if isempty(curve)
    warnOnceIdentity();
    volts = powerMw;
else
    v = curve.voltage(:);
    p = curve.powerAtSample(:);
    [p, order] = sort(p);
    v = v(order);
    volts = interp1(p, v, min(max(powerMw, p(1)), p(end)), 'linear');
end

volts = min(max(volts, 0), maxV);
end

function warnOnceIdentity()
persistent warned
if isempty(warned)
    warning('sem:util:laserVoltsForMw:noPowerCurve', ...
        ['No power calibration found — treating mW as volts (identity). ' ...
         'Run scripts/run_power_calibration.m before real experiments.']);
    warned = true;
end
end
