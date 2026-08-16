function notifyStim(daq, ev)
%notifyStim Forward a stim-event announcement to mock DAQs; no-op on real ones.
%   sem.hardware.notifyStim(daq, ev) calls daq.setActiveStim(ev) iff the DAQ
%   implements it (MockEphysDAQ). Real DAQs ignore the announcement — the
%   same pattern the DMD repo uses for ScanImageBridge.setActivePattern.
%   Experiments must always route through this helper rather than calling
%   mock-only methods directly, so the same code path runs on the rig.
if ismethod(daq, 'setActiveStim')
    daq.setActiveStim(ev);
end
end
