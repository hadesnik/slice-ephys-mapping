%run_power_calibration Laser AO volts -> mW at sample (Phase B, rig PC).
%   Wraps tfp.calibration.powerMeterSweep: steps the laser-modulation AO
%   (config.daq.ao_laser) through a voltage ladder while you read the power
%   meter at the sample plane, then saves the curve with
%   tfp.io.saveCalibration. sem.util.laserVoltsForMw consumes the result
%   (set laser.calibration_file in configs/slice_rig.yaml to the saved path).
%
%   Run on the rig PC with the power meter under the objective:
%       run(fullfile('scripts', 'run_power_calibration.m'))

thisDir = fileparts(mfilename('fullpath'));
run(fullfile(thisDir, '..', 'sem_setup.m'));

config = tfp.io.loadConfig(fullfile(thisDir, '..', 'configs', 'slice_rig.yaml'));
if ~strcmpi(config.hardwareKind, 'real')
    error('run_power_calibration:mockConfig', 'Run against slice_rig.yaml on the rig PC.');
end

daq = tfp.hardware.NI6323_DAQ(config.daq);
cleanupObj = onCleanup(@() daq.cleanup()); %#ok<NASGU>

% See the DMD repo's run_powerMeterSweep for the full-featured version;
% this thin wrapper keeps the sem-side entry point stable.
calib = tfp.calibration.powerMeterSweep(daq, struct( ...
    'aoChannel', sprintf('ao%d', config.daq.ao_laser), ...
    'maxVoltage', config.laser.ao_voltage_max));

path = tfp.io.saveCalibration(calib, 'power_curve', config);
fprintf(['Saved %s\nPoint laser.calibration_file at it in configs/slice_rig.yaml ' ...
         '(tfp.io.updateConfigCalibrationPath does the edit).\n'], path);
