function sealTestStruct = nestSealTestCfg(sealCfg)
%nestSealTestCfg Flat sem config keys -> nested seal-test struct.
%   sealTestStruct = sem.util.nestSealTestCfg(sealCfg)
%
%   Inverse of sem.util.flattenSealTestCfg: turns the flat rig-config keys
%   (config.ephys.sealTest_preMs, ...) into the nested struct the GUI layer's
%   patchclamp.config.TrialConfig expects. This is how the rig YAML becomes the
%   single source of truth for the GUI's seal-test defaults instead of the
%   hard-coded values in TrialConfig.defaultConfig.
%
%   Defaults match configs/slice_rig.yaml's ephys section.

if ~isstruct(sealCfg) || ~isscalar(sealCfg)
    error('sem:util:nestSealTestCfg:badInput', ...
        'sealCfg must be a scalar struct.');
end

sealTestStruct = struct( ...
    'preMs',           sem.util.configField(sealCfg, 'sealTest_preMs', 20), ...
    'stepMs',          sem.util.configField(sealCfg, 'sealTest_stepMs', 100), ...
    'postMs',          sem.util.configField(sealCfg, 'sealTest_postMs', 30), ...
    'amplitudeVcMv',   sem.util.configField(sealCfg, 'sealTest_amplitudeVcMv', -5), ...
    'amplitudeIcPa',   sem.util.configField(sealCfg, 'sealTest_amplitudeIcPa', -20));
end
