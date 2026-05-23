classdef IntegrationR1_FakeBackendAndSeal < matlab.unittest.TestCase
    % IntegrationR1_FakeBackendAndSeal  Cross-component test for Round 1.
    %
    % Inside R1 each agent worked in isolation against contracts. This test wires
    % the pieces together so any drift between the synthesis (FakeBackend) and the
    % analysis (Seal) shows up in a regression run.
    %
    % Loop tested:
    %   FakeTelegraph (mode + gain) -> Trial.compose (AO0 in cell units)
    %                               -> FakeBackend.configureTrial + run -> AI in cell units
    %                               -> Seal.analyzeTrial -> rsMohm / riMohm / holding
    %   The fake's ground-truth properties must be recovered by Seal within tolerance.

    methods (Test)
        function testVcRecoversGroundTruthRsRiHolding(testCase)
            rng(42);

            mode = "VC";
            telegraph = patchclamp.hardware.FakeTelegraph();
            telegraph.setMode(mode);

            backend = patchclamp.hardware.FakeBackend(telegraph);
            backend.RsMOhm       = 18;
            backend.RinputMOhm   = 220;
            backend.CmPicoF      = 80;
            backend.VrestMv      = -65;
            backend.VholdMv      = -70;
            backend.noiseRmsPaVc = 4;
            backend.rngSeed      = 12345;

            cfg = patchclamp.config.TrialConfig.defaultConfig();
            % Force VC seal-test amplitude to the canonical -5 mV in case the default drifts.
            cfg.sealTest.amplitudeVcMv = -5;
            cfg.mode = mode;

            [ao0CellUnits, ao2Volts, layout] = patchclamp.protocol.Trial.compose(cfg, mode);

            backend.configureTrial(ao0CellUnits, ao2Volts, "ai1", cfg.sampleRateHz, cfg.trialLengthSec);
            ai = backend.run();

            result = patchclamp.analysis.Seal.analyzeTrial( ...
                ai, mode, cfg.sealTest, cfg.sampleRateHz, layout);

            % Ground-truth holding current at the cell in VC, in pA:
            % (Vhold - Vrest)/Rinput in mV/MOhm = nA -> *1000 -> pA.
            expectedHoldingPa = (backend.VholdMv - backend.VrestMv) / backend.RinputMOhm * 1000;

            testCase.verifyEqual(result.mode, mode);
            testCase.verifyEqual(result.holdingUnit, "pA");
            testCase.verifyEqual(result.holding, expectedHoldingPa, "AbsTol", 3);     % within 3 pA of ground truth
            testCase.verifyEqual(result.rsMohm,  backend.RsMOhm,     "RelTol", 0.10); % within 10% of ground truth
            testCase.verifyEqual(result.riMohm,  backend.RinputMOhm, "RelTol", 0.05); % within 5%
        end

        function testIcRecoversGroundTruthRiAndVrest(testCase)
            rng(7);

            mode = "IC";
            telegraph = patchclamp.hardware.FakeTelegraph();
            telegraph.setMode(mode);

            backend = patchclamp.hardware.FakeBackend(telegraph);
            backend.RinputMOhm   = 180;
            backend.CmPicoF      = 90;
            backend.VrestMv      = -62;
            backend.IholdPa      = 0;
            backend.noiseRmsMvIc = 0.25;
            backend.rngSeed      = 99;

            cfg = patchclamp.config.TrialConfig.defaultConfig();
            cfg.sealTest.amplitudeIcPa = -100;
            cfg.mode = mode;

            [ao0CellUnits, ao2Volts, layout] = patchclamp.protocol.Trial.compose(cfg, mode);

            backend.configureTrial(ao0CellUnits, ao2Volts, "ai1", cfg.sampleRateHz, cfg.trialLengthSec);
            ai = backend.run();

            result = patchclamp.analysis.Seal.analyzeTrial( ...
                ai, mode, cfg.sealTest, cfg.sampleRateHz, layout);

            testCase.verifyEqual(result.mode, mode);
            testCase.verifyEqual(result.holdingUnit, "mV");
            testCase.verifyTrue(isnan(result.rsMohm), "Rs must be NaN in IC mode");
            testCase.verifyEqual(result.holding,  backend.VrestMv,    "AbsTol", 1.0);   % within 1 mV
            testCase.verifyEqual(result.riMohm,   backend.RinputMOhm, "RelTol", 0.05);  % within 5%
        end

        function testStorageWriterAcceptsLiveTrialResult(testCase)
            % Wire in Agent D: build a TrialResult-shaped struct from the live loop,
            % round-trip it through Hdf5Writer, peek the file back.
            rng(123);

            telegraph = patchclamp.hardware.FakeTelegraph();
            backend   = patchclamp.hardware.FakeBackend(telegraph);
            backend.rngSeed = 1;

            cfg = patchclamp.config.TrialConfig.defaultConfig();
            mode = telegraph.getMode();
            cfg.mode = mode;

            [ao0CellUnits, ao2Volts, layout] = patchclamp.protocol.Trial.compose(cfg, mode);
            backend.configureTrial(ao0CellUnits, ao2Volts, "ai1", cfg.sampleRateHz, cfg.trialLengthSec);
            ai = backend.run();
            seal = patchclamp.analysis.Seal.analyzeTrial(ai, mode, cfg.sealTest, cfg.sampleRateHz, layout);

            trialResult = struct( ...
                'aiCellUnits',        ai, ...
                'aoCommandCellUnits', ao0CellUnits, ...
                'aoLedVolts',         ao2Volts, ...
                'rsMohm',             seal.rsMohm, ...
                'riMohm',             seal.riMohm, ...
                'holding',            seal.holding, ...
                'holdingUnit',        seal.holdingUnit, ...
                'mode',               mode, ...
                'sampleRateHz',       cfg.sampleRateHz, ...
                'timestamp',          string(datetime("now","Format","yyyy-MM-dd'T'HH:mm:ss")), ...
                'gainSnapshot',       telegraph.getGain());

            filePath = [tempname '.h5'];
            cleanupObj = onCleanup(@() iDeleteIfExists(filePath));

            sessionMeta = struct('cellId', "integ-cell", 'config', cfg);
            writer = patchclamp.storage.Hdf5Writer(filePath, sessionMeta);
            writer.appendTrial(trialResult);
            writer.appendTrial(trialResult);
            writer.close();

            testCase.verifyEqual(patchclamp.storage.Hdf5Writer.peekTrialCount(filePath), uint32(2));

            % Spot-check that the AI vector round-trips losslessly.
            aiBack = h5read(filePath, '/trials/000000/aiCellUnits');
            testCase.verifyEqual(aiBack, ai, "AbsTol", 1e-12);
        end
    end
end

function iDeleteIfExists(p)
    if exist(p, "file") == 2
        delete(p);
    end
end
