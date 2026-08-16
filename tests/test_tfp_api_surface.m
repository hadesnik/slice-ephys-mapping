classdef test_tfp_api_surface < matlab.unittest.TestCase
    %test_tfp_api_surface Tripwire on the tfp API surface this repo depends on.
    %   The cross-repo analogue of the DMD repo's test_optics_handoff_constants:
    %   sem consumes tfp as a library with no package manager, so an upstream
    %   rename/refactor would otherwise surface as a rig-day failure. Every
    %   entry point named in docs/DEPENDENCIES.md gets an existence check here,
    %   plus behavioral spot-checks on the contracts sem actually leans on
    %   (multi-AO queueClockedAO, the on-fraction safety cap, fillFactorEnsemble
    %   permutations, saveTrial metadata passthrough).

    properties
        TmpDir
    end

    methods (TestMethodSetup)
        function makeTmp(tc)
            tc.TmpDir = tempname();
            mkdir(tc.TmpDir);
        end
    end

    methods (TestMethodTeardown)
        function rmTmp(tc)
            if isfolder(tc.TmpDir)
                rmdir(tc.TmpDir, 's');
            end
        end
    end

    methods (Test)
        function entryPoints_exist(tc)
            entryPoints = { ...
                'tfp.io.loadConfig', 'tfp.io.saveTrial', 'tfp.io.sessionLog', ...
                'tfp.io.saveCalibration', 'tfp.io.loadCalibration', ...
                'tfp.io.receiveROIsFromScanImage', 'tfp.io.parseRoiPayload', ...
                'tfp.patterns.singleSpot', 'tfp.patterns.multiSpot', ...
                'tfp.patterns.fillFactorEnsemble', 'tfp.patterns.calibratedAffine', ...
                'tfp.calibration.alignDMDtoCamera', 'tfp.calibration.powerMeterSweep', ...
                'tfp.analysis.responseClassifier', ...
                'tfp.util.configField', 'tfp.util.safetyChecks', ...
                'tfp.util.readHandoffConstants'};
            for i = 1:numel(entryPoints)
                tc.verifyNotEmpty(which(entryPoints{i}), ...
                    sprintf('tfp entry point missing: %s', entryPoints{i}));
            end
            classes = {'tfp.hardware.DAQ', 'tfp.hardware.DMD', ...
                'tfp.hardware.MockDMD', 'tfp.hardware.MockDAQ', ...
                'tfp.trial.Trial', 'tfp.trial.TrialSequence'};
            for i = 1:numel(classes)
                tc.verifyNotEmpty(meta.class.fromName(classes{i}), ...
                    sprintf('tfp class missing: %s', classes{i}));
            end
        end

        function handoff_has_on_fraction_cap(tc)
            c = tfp.util.readHandoffConstants();
            tc.verifyTrue(isfield(c, 'on_fraction_cap'));
            tc.verifyGreaterThan(c.on_fraction_cap, 0);
            tc.verifyLessThanOrEqual(c.on_fraction_cap, 1);
        end

        function mockdmd_enforces_on_fraction_cap(tc)
            dmd = tfp.hardware.MockDMD();
            dmd.initialize(struct('nRows', 100, 'nCols', 100, ...
                'loadLatencyMsPerPattern', 0));
            over = false(100, 100);
            over(1:80, :) = true;   % 80% ON > 50% cap
            tc.verifyError(@() dmd.loadPatternSequence(over, ...
                struct('exposureUs', 1000, 'darkTimeUs', 100)), ...
                'tfp:hardware:DMD:onFractionExceeded');
        end

        function fillFactorEnsemble_permutations_nest(tc)
            dmd = struct('nRows', 200, 'nCols', 200);
            centroids = [100, 100];
            [p1, info1] = tfp.patterns.fillFactorEnsemble(dmd, centroids, 10, 0.3, ...
                struct('rngSeed', 7));
            [p2, ~] = tfp.patterns.fillFactorEnsemble(dmd, centroids, 10, 0.6, ...
                struct('permutations', {info1.permutations}));
            % Nested subsets: every 30% pixel is inside the 60% set.
            tc.verifyTrue(all(p2(p1)));
        end

        function queueClockedAO_validates_multichannel_width(tc)
            daq = tfp.hardware.MockDAQ();
            daq.initialize(struct('sampleRate', 1000));
            daq.startContinuousSession(struct('sampleRate', 1000, ...
                'aiChannels', [], 'aoChannels', [0, 1]));
            % The multi-AO contract sem relies on: Nx2 accepted, Nx1 rejected.
            idx = daq.queueClockedAO(zeros(10, 2), 1000, 'immediate');
            tc.verifyClass(idx, 'uint64');
            tc.verifyError(@() daq.queueClockedAO(zeros(10, 1), 1000, 'immediate'), ...
                'tfp:hardware:DAQ:badShape');
            daq.stopContinuousSession();
        end

        function saveTrial_roundtrips_ephys_metadata(tc)
            tr = tfp.trial.Trial();
            tr.trialIdx = 1;
            tr.metadata = struct('ephys', struct('schemaVersion', 1, ...
                'clampMode', 'VC', 'holdingMv', -70));
            tr.markRunning();
            tr.markComplete(struct('aiData', zeros(5, 2)));
            metaPath = tfp.io.saveTrial(tr, tc.TmpDir);
            loaded = load(metaPath);
            tc.verifyEqual(loaded.meta.metadata.ephys.holdingMv, -70);
            tc.verifyEqual(loaded.meta.metadata.ephys.clampMode, 'VC');
        end
    end
end
