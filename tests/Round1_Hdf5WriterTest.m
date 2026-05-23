classdef Round1_Hdf5WriterTest < matlab.unittest.TestCase
    % Round1_Hdf5WriterTest  Tests for patchclamp.storage.Hdf5Writer.

    properties
        FilePath (1,1) string
    end

    methods (TestMethodSetup)
        function pickFilePath(tc)
            tc.FilePath = string(tempname()) + ".h5";
        end
    end

    methods (TestMethodTeardown)
        function removeFile(tc)
            if exist(tc.FilePath, "file") == 2
                delete(tc.FilePath);
            end
        end
    end

    methods (Static, Access = private)
        function meta = defaultMeta()
            cfg = patchclamp.config.TrialConfig.defaultConfig();
            meta = struct("cellId", "CELL_TEST", "config", cfg);
        end

        function tr = makeTrial(nSamples, mode, holdingUnit)
            arguments
                nSamples (1,1) double = 100
                mode (1,1) string = "VC"
                holdingUnit (1,1) string = "pA"
            end
            t = (0:nSamples-1)' / 20000;
            tr = struct( ...
                'aiCellUnits',        sin(2*pi*50*t), ...
                'aoCommandCellUnits', zeros(nSamples,1), ...
                'aoLedVolts',         zeros(nSamples,1), ...
                'rsMohm',             12.5, ...
                'riMohm',             250.0, ...
                'holding',            -65.0, ...
                'holdingUnit',        holdingUnit, ...
                'mode',               mode, ...
                'sampleRateHz',       20000, ...
                'timestamp',          "2026-05-23T12:00:00-07:00", ...
                'gainSnapshot',       struct( ...
                    'commandVcMvPerV', 20, ...
                    'commandIcPaPerV', 400, ...
                    'scaledVcPaPerV',  1000, ...
                    'scaledIcMvPerMv', 20));
        end
    end

    methods (Test)
        function testCreatesFileAndMetaGroup(tc)
            w = patchclamp.storage.Hdf5Writer(tc.FilePath, tc.defaultMeta()); %#ok<NASGU>
            tc.verifyTrue(exist(tc.FilePath, "file") == 2, "File was not created.");

            % All three meta datasets exist and round-trip as strings.
            cfgRead = h5read(tc.FilePath, "/meta/config");
            tc.verifyClass(cfgRead, "string");
            tc.verifyGreaterThan(strlength(cfgRead), 0);

            tsRead = h5read(tc.FilePath, "/meta/startTimestamp");
            tc.verifyGreaterThan(strlength(tsRead), 0);

            cellIdRead = h5read(tc.FilePath, "/meta/cellId");
            tc.verifyEqual(string(cellIdRead), "CELL_TEST");
        end

        function testRefusesToOverwriteExisting(tc)
            % Pre-create the file (any HDF5 content; we just need it to exist).
            h5create(tc.FilePath, "/placeholder", 1);
            h5write(tc.FilePath, "/placeholder", 0);
            tc.verifyError( ...
                @() patchclamp.storage.Hdf5Writer(tc.FilePath, tc.defaultMeta()), ...
                "patchclamp:storage:FileExists");
        end

        function testAppendTrialCreatesGroup(tc)
            w = patchclamp.storage.Hdf5Writer(tc.FilePath, tc.defaultMeta());
            tr = tc.makeTrial(256);
            w.appendTrial(tr);
            w.close();

            ai = h5read(tc.FilePath, "/trials/000000/aiCellUnits");
            tc.verifySize(ai, [256, 1]);
            tc.verifyEqual(ai, tr.aiCellUnits, "AbsTol", 1e-12);
        end

        function testAppendTrialStoresGainSnapshot(tc)
            w = patchclamp.storage.Hdf5Writer(tc.FilePath, tc.defaultMeta());
            tr = tc.makeTrial();
            w.appendTrial(tr);
            w.close();

            g = "/trials/000000/gainSnapshot";
            tc.verifyEqual(h5readatt(tc.FilePath, g, "commandVcMvPerV"), 20);
            tc.verifyEqual(h5readatt(tc.FilePath, g, "commandIcPaPerV"), 400);
            tc.verifyEqual(h5readatt(tc.FilePath, g, "scaledVcPaPerV"),  1000);
            tc.verifyEqual(h5readatt(tc.FilePath, g, "scaledIcMvPerMv"), 20);
        end

        function testTrialIndexIncrements(tc)
            w = patchclamp.storage.Hdf5Writer(tc.FilePath, tc.defaultMeta());
            for k = 1:3
                w.appendTrial(tc.makeTrial(32));
            end
            w.close();

            for k = 0:2
                ai = h5read(tc.FilePath, sprintf("/trials/%06u/aiCellUnits", k));
                tc.verifySize(ai, [32, 1]);
            end
            tc.verifyEqual(patchclamp.storage.Hdf5Writer.peekTrialCount(tc.FilePath), uint32(3));
        end

        function testCloseIsIdempotent(tc)
            w = patchclamp.storage.Hdf5Writer(tc.FilePath, tc.defaultMeta());
            w.close();
            tc.verifyWarningFree(@() w.close());
            tc.verifyFalse(w.IsOpen);
        end

        function testAppendAfterCloseErrors(tc)
            w = patchclamp.storage.Hdf5Writer(tc.FilePath, tc.defaultMeta());
            w.close();
            tc.verifyError(@() w.appendTrial(tc.makeTrial()), ...
                "patchclamp:storage:NotOpen");
        end

        function testCrashSimulation(tc)
            % Construct, append 2 trials, then drop the handle without close().
            % File on disk must still be a valid HDF5 with both trials intact.
            w = patchclamp.storage.Hdf5Writer(tc.FilePath, tc.defaultMeta());
            w.appendTrial(tc.makeTrial(64));
            w.appendTrial(tc.makeTrial(64));
            clear w;  %#ok<CLEAR>  % mimics a crash / lost handle

            tc.verifyEqual( ...
                patchclamp.storage.Hdf5Writer.peekTrialCount(tc.FilePath), uint32(2));

            ai0 = h5read(tc.FilePath, "/trials/000000/aiCellUnits");
            ai1 = h5read(tc.FilePath, "/trials/000001/aiCellUnits");
            tc.verifySize(ai0, [64, 1]);
            tc.verifySize(ai1, [64, 1]);
        end

        function testPeekTrialCount(tc)
            % Standalone: write a session, then ask peekTrialCount.
            w = patchclamp.storage.Hdf5Writer(tc.FilePath, tc.defaultMeta());
            for k = 1:5
                w.appendTrial(tc.makeTrial(16));
            end
            w.close();
            tc.verifyEqual( ...
                patchclamp.storage.Hdf5Writer.peekTrialCount(tc.FilePath), uint32(5));
        end

        function testHoldingUnitStored(tc)
            % VC case -> pA
            w = patchclamp.storage.Hdf5Writer(tc.FilePath, tc.defaultMeta());
            w.appendTrial(tc.makeTrial(8, "VC", "pA"));
            w.close();
            unitVc = h5readatt(tc.FilePath, "/trials/000000", "holdingUnit");
            tc.verifyEqual(string(unitVc), "pA");

            % IC case -> mV (separate file)
            tc.removeFile();
            tc.pickFilePath();
            w2 = patchclamp.storage.Hdf5Writer(tc.FilePath, tc.defaultMeta());
            w2.appendTrial(tc.makeTrial(8, "IC", "mV"));
            w2.close();
            unitIc = h5readatt(tc.FilePath, "/trials/000000", "holdingUnit");
            tc.verifyEqual(string(unitIc), "mV");
        end

        function testModeStored(tc)
            % Both VC and IC round-trip as strings.
            w = patchclamp.storage.Hdf5Writer(tc.FilePath, tc.defaultMeta());
            w.appendTrial(tc.makeTrial(8, "VC", "pA"));
            w.appendTrial(tc.makeTrial(8, "IC", "mV"));
            w.close();

            m0 = h5readatt(tc.FilePath, "/trials/000000", "mode");
            m1 = h5readatt(tc.FilePath, "/trials/000001", "mode");
            tc.verifyEqual(string(m0), "VC");
            tc.verifyEqual(string(m1), "IC");
        end
    end
end
