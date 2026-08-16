classdef test_config_examples < matlab.unittest.TestCase
    %test_config_examples Every shipped config must parse with tfp's hand
    %   YAML parser and carry the keys the runner/experiments read. The
    %   slice_rig config must keep its %VERIFY markers until Phase B closes
    %   them on the rig — their disappearance without a bringup is a red flag.

    methods (Test)
        function mock_yaml_parses_with_required_keys(tc)
            config = tfp.io.loadConfig(configPath('mock.yaml'));
            tc.verifyEqual(lower(config.hardwareKind), 'mock');
            requiredSections = {'paths', 'daq', 'ephys', 'dmd', 'laser', ...
                'timing', 'fov', 'ensemble', 'ppsf', 'groundTruth', 'ui'};
            for i = 1:numel(requiredSections)
                tc.verifyTrue(isfield(config, requiredSections{i}), ...
                    sprintf('mock.yaml missing section: %s', requiredSections{i}));
            end
            tc.verifyTrue(all(isfield(config.daq, {'sampleRate', ...
                'analogInChannels', 'ai_scaledOutput', 'ao_laser', 'ao_cellCommand'})));
            tc.verifyTrue(all(isfield(config.ephys, {'commandVcMvPerV', ...
                'scaledVcPaPerV', 'sealTest_preMs', 'holdingVcEMv', 'holdingVcIMv'})));
            tc.verifyTrue(all(isfield(config.timing, {'stimDurS', 'itiMeanS', ...
                'preS', 'postS'})));
            tc.verifyTrue(iscell(config.ensemble.blocks) ...
                || ischar(config.ensemble.blocks));
        end

        function slice_rig_yaml_parses(tc)
            config = tfp.io.loadConfig(configPath('slice_rig.yaml'));
            tc.verifyEqual(lower(config.hardwareKind), 'real');
            tc.verifyTrue(all(isfield(config.daq, {'ai_scaledOutput', ...
                'ao_laser', 'ao_cellCommand'})));
            tc.verifyTrue(isfield(config.dmd, 'chunkSize'));
        end

        function slice_rig_keeps_verify_markers(tc)
            raw = fileread(configPath('slice_rig.yaml'));
            n = numel(strfind(raw, '%VERIFY'));
            tc.verifyGreaterThan(n, 10, ...
                ['slice_rig.yaml lost its %VERIFY markers — only remove them ' ...
                 'as each wire is confirmed during Phase B bringup.']);
        end

        function ensemble_blocks_are_valid_labels(tc)
            config = tfp.io.loadConfig(configPath('mock.yaml'));
            blocks = config.ensemble.blocks;
            if ~iscell(blocks), blocks = cellstr(blocks); end
            for i = 1:numel(blocks)
                tc.verifyTrue(ismember(blocks{i}, {'CC', 'VC-70', 'VC+10'}), ...
                    sprintf('bad block label in mock.yaml: %s', blocks{i}));
            end
        end
    end
end

% --- Local helpers ---

function p = configPath(name)
thisDir = fileparts(mfilename('fullpath'));
p = fullfile(thisDir, '..', 'configs', name);
end
