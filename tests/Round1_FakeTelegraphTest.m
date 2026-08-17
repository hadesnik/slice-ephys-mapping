classdef Round1_FakeTelegraphTest < matlab.unittest.TestCase
    % Round1_FakeTelegraphTest  Exercises the FakeTelegraph programmable mock.
    %
    % Verifies: defaults; mode/gain getters; ModeChanged / GainChanged events
    % fire only on real transitions and carry the new value in their event data.

    methods (Test)
        function testDefaultsMatchContract(tc)
            tele = patchclamp.hardware.FakeTelegraph();
            tc.verifyEqual(tele.getMode(), "VC");
            g = tele.getGain();
            tc.verifyEqual(g.commandVcMvPerV, 20);
            tc.verifyEqual(g.commandIcPaPerV, 400);
            tc.verifyEqual(g.scaledVcPaPerV,  1000);
            tc.verifyEqual(g.scaledIcMvPerMv, 20);
        end

        function testConstructorOverridesMode(tc)
            tele = patchclamp.hardware.FakeTelegraph(mode = "IC");
            tc.verifyEqual(tele.getMode(), "IC");
        end

        function testConstructorOverridesGain(tc)
            g = struct( ...
                'commandVcMvPerV', 10, ...
                'commandIcPaPerV', 200, ...
                'scaledVcPaPerV',  500, ...
                'scaledIcMvPerMv', 50);
            tele = patchclamp.hardware.FakeTelegraph(gain = g);
            tc.verifyEqual(tele.getGain(), g);
        end

        function testStartStopAreNoOps(tc)
            tele = patchclamp.hardware.FakeTelegraph();
            tele.start();
            tele.stop();
            tele.start();  % idempotent
            tele.stop();
            tc.verifyEqual(tele.getMode(), "VC");
        end

        function testSetModeFiresEventWithNewMode(tc)
            tele = patchclamp.hardware.FakeTelegraph();
            captured = struct('count', 0, 'lastMode', "");
            lh = addlistener(tele, "ModeChanged", @onModeChanged); %#ok<NASGU>
            tele.setMode("IC");
            tc.verifyEqual(captured.count, 1);
            tc.verifyEqual(captured.lastMode, "IC");
            tc.verifyEqual(tele.getMode(), "IC");

            function onModeChanged(src, ~)
                captured.count = captured.count + 1;
                captured.lastMode = src.getMode();
            end
        end

        function testSetModeNoChangeDoesNotFire(tc)
            tele = patchclamp.hardware.FakeTelegraph();  % default VC
            counter = struct('n', 0);
            lh = addlistener(tele, "ModeChanged", @(~,~) increment()); %#ok<NASGU>
            tele.setMode("VC");
            tc.verifyEqual(counter.n, 0);

            function increment()
                counter.n = counter.n + 1;
            end
        end

        function testSetGainFiresOnlyWhenChanged(tc)
            tele = patchclamp.hardware.FakeTelegraph();
            captured = struct('count', 0, 'lastGain', struct());
            lh = addlistener(tele, "GainChanged", @onGainChanged); %#ok<NASGU>

            % Setting to current value -> no event.
            tele.setGain(tele.getGain());
            tc.verifyEqual(captured.count, 0);

            % Setting to a different value -> exactly one event.
            newGain = tele.getGain();
            newGain.scaledVcPaPerV = 2000;
            tele.setGain(newGain);
            tc.verifyEqual(captured.count, 1);
            tc.verifyEqual(captured.lastGain.scaledVcPaPerV, 2000);
            tc.verifyEqual(tele.getGain().scaledVcPaPerV, 2000);

            function onGainChanged(src, ~)
                captured.count = captured.count + 1;
                captured.lastGain = src.getGain();
            end
        end

        function testSetModeRejectsBadValue(tc)
            tele = patchclamp.hardware.FakeTelegraph();
            tc.verifyError(@() tele.setMode("FOO"), ?MException);
        end

        function testSetGainRejectsMissingField(tc)
            tele = patchclamp.hardware.FakeTelegraph();
            bad = struct('commandVcMvPerV', 20, 'commandIcPaPerV', 400, ...
                         'scaledVcPaPerV', 1000);  % missing scaledIcMvPerMv
            tc.verifyError(@() tele.setGain(bad), ...
                "patchclamp:hardware:FakeTelegraph:missingGainField");
        end
    end
end
