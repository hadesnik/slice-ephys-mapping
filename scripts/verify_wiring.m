%verify_wiring Phase B hardware acceptance: close the %VERIFY markers.
%   Interactive checklist run on the rig PC with configs/slice_rig.yaml.
%   Each section prints what to connect and what to expect; nothing here is
%   automated sign-off — YOU confirm each wire on a scope / meter, then edit
%   the config and docs/WIRING.md and delete that line's %VERIFY marker.
%
%   Checks:
%     1. AO loopback     — ao_laser and ao_cellCommand each driven with a
%                          1 V step while looped into a spare AI; verifies
%                          channel identity and sign.
%     2. AO idle level   — after a queued waveform ends, the AO must HOLD its
%                          last sample (the holding convention the runner
%                          relies on). Scope the line after a queue drains.
%     3. Scaled output   — with a model cell on the 700B in VC, a -5 mV seal
%                          step must appear on ai_scaledOutput with the
%                          front-panel gain (config ephys.scaledVcPaPerV).
%     4. do_sync         — 5 ms TTL visible on the scope at block start.
%
%   Usage (rig PC): run(fullfile('scripts', 'verify_wiring.m'))

thisDir = fileparts(mfilename('fullpath'));
run(fullfile(thisDir, '..', 'sem_setup.m'));

config = tfp.io.loadConfig(fullfile(thisDir, '..', 'configs', 'slice_rig.yaml'));
if ~strcmpi(config.hardwareKind, 'real')
    error('verify_wiring:mockConfig', 'verify_wiring must run against slice_rig.yaml on the rig PC.');
end

fprintf('\n=== verify_wiring: slice-rig NI channel acceptance ===\n');
fprintf('Config: ao_laser=ao%d  ao_cellCommand=ao%d  ai_scaledOutput=ai%d  do_sync=%s\n\n', ...
    config.daq.ao_laser, config.daq.ao_cellCommand, config.daq.ai_scaledOutput, ...
    config.daq.do_sync);

daq = tfp.hardware.NI6323_DAQ(config.daq);
cleanupObj = onCleanup(@() daq.cleanup()); %#ok<NASGU>

% --- 1. AO identity: drive each AO in turn, operator confirms on scope ----
for ao = [config.daq.ao_laser, config.daq.ao_cellCommand]
    input(sprintf('Scope ao%d, press Enter to drive it to 1.0 V for 2 s...', ao), 's');
    daq.outputSingleAnalog(sprintf('ao%d', ao), 1.0);
    pause(2);
    daq.outputSingleAnalog(sprintf('ao%d', ao), 0.0);
    input('Confirm you saw the 1 V step on the intended wire (Enter = yes)...', 's');
end

% --- 2. AO idle-at-last-sample convention ---------------------------------
fprintf(['\nQueue test: a clocked waveform ending at 0.5 V will be queued on the\n' ...
         'continuous session; after it drains the line must SIT at 0.5 V.\n']);
input('Scope ao_cellCommand, press Enter...', 's');
daq.startContinuousSession(struct('sampleRate', config.daq.sampleRate, ...
    'aiChannels', [], 'aoChannels', [config.daq.ao_laser, config.daq.ao_cellCommand]));
w = [zeros(1000, 1), [linspace(0, 0.5, 999)'; 0.5]];
daq.queueClockedAO(w, config.daq.sampleRate, 'immediate');
pause(1.0);
resp = input('Is the line holding at 0.5 V after the ramp ended? (y/n) ', 's');
daq.queueClockedAO(zeros(10, 2), config.daq.sampleRate, 'immediate');
daq.stopContinuousSession();
if ~strcmpi(strtrim(resp), 'y')
    warning('verify_wiring:aoIdle', ...
        ['AO does NOT idle at the last written sample — the software-holding ' ...
         'design is unsafe on this board config. STOP and resolve before Phase C.']);
end

% --- 3 & 4: printed instructions (need the amplifier / scope in the loop) --
fprintf(['\nRemaining manual checks:\n' ...
    ' 3. Model cell on the 700B, VC: run a seal test (sem.protocol.sealTestWaveform\n' ...
    '    -> Units.commandCellToDaqVolts -> queueClockedAO) and check the response\n' ...
    '    amplitude on ai%d matches ephys.scaledVcPaPerV.\n' ...
    ' 4. Block-start do_sync pulse: run any mock-config block pointed at this DAQ\n' ...
    '    and confirm a 5 ms TTL on %s.\n' ...
    'Update configs/slice_rig.yaml + docs/WIRING.md and remove each %%VERIFY as confirmed.\n'], ...
    config.daq.ai_scaledOutput, config.daq.do_sync);
