function trialConfig = trialConfigFromSemConfig(config)
%trialConfigFromSemConfig Rig YAML -> the GUI's TrialConfig.
%   trialConfig = sem.gui.trialConfigFromSemConfig(config)
%
%   Makes configs/*.yaml the single source of truth for the patching GUI's
%   defaults instead of the hard-coded values in TrialConfig.defaultConfig, so
%   the seal-test parameters the GUI runs are the same ones the block engine
%   runs and the same ones that land in every trial's metadata.
%
%   Mapped: config.daq.sampleRate -> sampleRateHz
%           config.ephys.sealTest_* -> sealTest (via sem.util.nestSealTestCfg)
%           config.ui.patchSweepRateHz -> itiSec (the membrane-test repeat rate)
%
%   The membrane test is seal-test only: no opto, no command train. The trial is
%   just long enough to clear patchclamp.protocol.Trial's fixed 300 ms preamble,
%   which keeps each sweep short so the display stays responsive.

dCfg = sem.util.configField(config, 'daq', struct());
eCfg = sem.util.configField(config, 'ephys', struct());
uCfg = sem.util.configField(config, 'ui', struct());

trialConfig = patchclamp.config.TrialConfig.defaultConfig();
trialConfig.sampleRateHz = sem.util.configField(dCfg, 'sampleRate', 20000);
trialConfig.sealTest = sem.util.nestSealTestCfg(eCfg);

% Trial length: the fixed preamble plus a short tail. Trial.compose places the
% seal test at sample 1 and opens the stimulus window at 300 ms, and MainWindow
% requires > 0.300 s, so 0.35 s is the shortest honest membrane-test sweep.
trialConfig.trialLengthSec = 0.35;

% Requested sweep rate, capped by the trial length: with the fixed 300 ms
% preamble a sweep cannot be shorter than trialLengthSec, so rates above
% ~1/trialLengthSec Hz simply mean "no gap between sweeps".
sweepHz = sem.util.configField(uCfg, 'patchSweepRateHz', 2);
if ~isfinite(sweepHz) || sweepHz <= 0
    sweepHz = 2;
end
trialConfig.itiSec = max(0, 1 / sweepHz - trialConfig.trialLengthSec);

trialConfig.mode = "VC";
trialConfig.opto = [];
trialConfig.commandStim = [];

patchclamp.config.TrialConfig.validate(trialConfig);
end
