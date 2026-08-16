function [dmd, daq] = makeRig(config)
%makeRig Instantiate the DMD and DAQ backends selected by config.hardwareKind.
%   [dmd, daq] = sem.hardware.makeRig(config)
%
%   'mock' -> tfp.hardware.MockDMD + sem.hardware.MockEphysDAQ (initialized).
%             Attach a ground-truth network afterwards:
%               model = sem.sim.makeGroundTruthNetwork(config, targets);
%               daq.attachNetworkModel(model);
%   'real' -> tfp.hardware.DLP650LNIR_DMD + tfp.hardware.NI6323_DAQ (their
%             constructors self-initialize, per the DMD repo convention).
%
%   The caller owns cleanup (onCleanup(@() ...) both objects).

kind = lower(char(sem.util.configField(config, 'hardwareKind', '')));
switch kind
    case 'mock'
        dmd = tfp.hardware.MockDMD();
        dmd.initialize(config.dmd);
        daq = sem.hardware.MockEphysDAQ();
        daq.initialize(config.daq);
    case 'real'
        dmd = tfp.hardware.DLP650LNIR_DMD(config.dmd);
        daq = tfp.hardware.NI6323_DAQ(config.daq);
    otherwise
        error('sem:hardware:makeRig:badKind', ...
            'config.hardwareKind must be ''mock'' or ''real''; got ''%s''.', kind);
end
end
