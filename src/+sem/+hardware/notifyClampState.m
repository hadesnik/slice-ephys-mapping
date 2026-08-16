function notifyClampState(daq, s)
%notifyClampState Forward the clamp state to mock DAQs; no-op on real ones.
%   sem.hardware.notifyClampState(daq, s) calls daq.setClampState(s) iff the
%   DAQ implements it (MockEphysDAQ). s: struct with mode ('VC'|'IC') and
%   holdingMv. On the real rig the amplifier owns the mode (operator prompt)
%   and the holding rides on the cell-command AO, so there is nothing to
%   forward — but the runner still calls this so mock and real share one
%   code path.
if ismethod(daq, 'setClampState')
    daq.setClampState(s);
end
end
