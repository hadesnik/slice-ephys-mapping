function sealCfg = flattenSealTestCfg(sealTestStruct)
%flattenSealTestCfg Nested seal-test struct -> flat sem config keys.
%   sealCfg = sem.util.flattenSealTestCfg(sealTestStruct)
%
%   The GUI layer (patchclamp.config.TrialConfig) carries seal-test parameters
%   as a NESTED struct (sealTest.preMs, sealTest.amplitudeVcMv, ...), because it
%   is built in MATLAB and never round-trips through YAML. The sem layer carries
%   the same parameters as FLAT keys (sealTest_preMs, sealTest_amplitudeVcMv,
%   ...), because tfp.io.loadConfig's hand parser supports only one level of
%   nesting (see CLAUDE.md).
%
%   This is the single translation point between the two shapes, so
%   sem.analysis.sealAnalysis and sem.protocol.sealTestWaveform stay the only
%   seal-test implementations in the repo regardless of which layer calls them.
%
%   Inverse: sem.util.nestSealTestCfg.

if ~isstruct(sealTestStruct) || ~isscalar(sealTestStruct)
    error('sem:util:flattenSealTestCfg:badInput', ...
        'sealTestStruct must be a scalar struct.');
end

sealCfg = struct( ...
    'sealTest_preMs',           sem.util.configField(sealTestStruct, 'preMs', 20), ...
    'sealTest_stepMs',          sem.util.configField(sealTestStruct, 'stepMs', 100), ...
    'sealTest_postMs',          sem.util.configField(sealTestStruct, 'postMs', 30), ...
    'sealTest_amplitudeVcMv',   sem.util.configField(sealTestStruct, 'amplitudeVcMv', -5), ...
    'sealTest_amplitudeIcPa',   sem.util.configField(sealTestStruct, 'amplitudeIcPa', -20));
end
