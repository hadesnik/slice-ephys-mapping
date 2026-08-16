classdef test_MockEphysDAQ < matlab.unittest.TestCase
    %test_MockEphysDAQ Contract parity + ground-truth synthesis of the mock DAQ.
    %   Verifies: the tfp.hardware.DAQ contract (shared error IDs for the
    %   continuous-session API), stim-event pairing with queueClockedAO
    %   onsets, the end-at-holding AO idle convention feeding the command
    %   reconstruction, clamp-mode freezing mid-session, and that an
    %   attached SliceNetworkModel actually shapes the returned AI.

    methods (Test)
        function is_a_tfp_daq(tc)
            daq = sem.hardware.MockEphysDAQ();
            tc.verifyTrue(isa(daq, 'tfp.hardware.DAQ'));
        end

        function continuous_contract_errors(tc)
            daq = sem.hardware.MockEphysDAQ();
            daq.initialize(basicDaqCfg());
            tc.verifyError(@() daq.stopContinuousSession(), 'tfp:hardware:DAQ:notRunning');
            tc.verifyError(@() daq.currentSampleIndex(), 'tfp:hardware:DAQ:notRunning');
            daq.startContinuousSession(struct('sampleRate', 20000, ...
                'aiChannels', [0, 1], 'aoChannels', [0, 1]));
            tc.verifyError(@() daq.startContinuousSession(struct('sampleRate', 20000)), ...
                'tfp:hardware:DAQ:alreadyRunning');
            tc.verifyError(@() daq.queueClockedAO(zeros(5, 1), 20000, 'immediate'), ...
                'tfp:hardware:DAQ:badShape');
            tc.verifyError(@() daq.queueClockedAO(zeros(5, 2), 10000, 'immediate'), ...
                'tfp:hardware:DAQ:badRate');
            tc.verifyError(@() daq.queueClockedAO(zeros(5, 2), 20000, 'sync'), ...
                'tfp:hardware:DAQ:notImplemented');
            r = daq.stopContinuousSession();
            tc.verifyEqual(size(r.aiData, 2), 2);
            tc.verifyEqual(r.sampleRate, 20000);
        end

        function stim_pairs_with_next_queue(tc)
            daq = sem.hardware.MockEphysDAQ();
            daq.initialize(basicDaqCfg());
            daq.startContinuousSession(struct('sampleRate', 20000, ...
                'aiChannels', [0], 'aoChannels', [0, 1]));
            daq.setActiveStim(struct('kind', 'ensemble', 'cellIds', [1, 2], ...
                'fillFractions', [1; 1], 'laserVolts', 2, 'durS', 0.01));
            onset1 = daq.queueClockedAO(zeros(10, 2), 20000, 'immediate');
            onset2 = daq.queueClockedAO(zeros(10, 2), 20000, 'immediate');
            daq.stopContinuousSession();
            ev = daq.getEvents();
            tc.verifyEqual(numel(ev), 2);
            tc.verifyEqual(ev(1).onset, double(onset1));
            tc.verifyEqual(ev(1).stim.kind, 'ensemble');
            tc.verifyEmpty(ev(2).stim);   % announcement consumed by first queue
            tc.verifyEqual(ev(2).onset, double(onset2));
        end

        function clamp_mode_frozen_while_running(tc)
            daq = sem.hardware.MockEphysDAQ();
            daq.initialize(basicDaqCfg());
            daq.setClampState(struct('mode', 'VC', 'holdingMv', -70));
            daq.startContinuousSession(struct('sampleRate', 20000, ...
                'aiChannels', [0], 'aoChannels', [0, 1]));
            % Holding may change mid-session; the mode may not.
            daq.setClampState(struct('mode', 'VC', 'holdingMv', 10));
            tc.verifyError(@() daq.setClampState(struct('mode', 'IC', 'holdingMv', 0)), ...
                'sem:hardware:MockEphysDAQ:modeChangeWhileRunning');
            daq.stopContinuousSession();
        end

        function model_shapes_ai_holding_and_epsc(tc)
            % End-to-end: holding command -> DC holding current; ensemble
            % stim -> inward EPSC at the paired onset.
            [daq, model] = modelBackedDaq();
            daq.setClampState(struct('mode', 'VC', 'holdingMv', -70));
            fs = 20000;
            daq.startContinuousSession(struct('sampleRate', fs, ...
                'aiChannels', [0, 1], 'aoChannels', [0, 1]));
            holdV = sem.util.Units.commandCellToDaqVolts(-70, 'VC', model.gain);
            daq.queueClockedAO([zeros(100, 1), repmat(holdV, 100, 1)], fs, 'immediate');
            pause(0.12);   % settle: AO idles at holding after the queue drains
            daq.setActiveStim(struct('kind', 'ensemble', ...
                'cellIds', model.cellIds, 'fillFractions', ones(model.nCells, 1), ...
                'centroids', model.dmdXY, 'laserVolts', 2, 'durS', 0.01));
            nStim = round(0.01 * fs);
            stimOnset = daq.queueClockedAO( ...
                [[repmat(2, nStim, 1); 0], repmat(holdV, nStim + 1, 1)], fs, 'immediate');
            pause(0.1);
            r = daq.stopContinuousSession();

            gain = model.gain;
            aiPa = sem.util.Units.scaledDaqVoltsToCell(r.aiData(:, 1), 'VC', gain);
            % DC holding current once settled: (Vhold - Vrest)/Rin * 1000.
            expectedPa = (-70 - model.params.vrestMv) / model.params.rinMohm * 1000;
            settledIdx = round(0.06 * fs):round(0.09 * fs);
            tc.verifyEqual(mean(aiPa(settledIdx)), expectedPa, 'RelTol', 0.2);
            % Evoked EPSC: post-onset window clearly more negative than baseline.
            o = double(stimOnset);
            evokedWin = aiPa(o + round(0.002 * fs) : min(end, o + round(0.03 * fs)));
            tc.verifyLessThan(min(evokedWin) - mean(aiPa(settledIdx)), -20);
        end

        function no_model_gives_noise(tc)
            daq = sem.hardware.MockEphysDAQ();
            daq.initialize(basicDaqCfg());
            daq.startContinuousSession(struct('sampleRate', 20000, ...
                'aiChannels', [0], 'aoChannels', [0, 1]));
            pause(0.05);
            r = daq.stopContinuousSession();
            tc.verifyLessThan(max(abs(r.aiData(:))), 1);   % just small noise
        end

        function getLog_schema(tc)
            daq = sem.hardware.MockEphysDAQ();
            daq.initialize(basicDaqCfg());
            entries = daq.getLog();
            tc.verifyTrue(all(isfield(entries, {'timestamp', 'eventType', 'payload'})));
            tc.verifyEqual(entries(1).eventType, 'initialize');
        end
    end
end

% --- Local helpers ---

function cfg = basicDaqCfg()
cfg = struct('sampleRate', 20000, 'analogInChannels', [0, 1], ...
    'analogOutChannels', [0, 1], 'digitalOutChannels', {{'port0/line0'}}, ...
    'digitalInChannels', {{}}, 'ai_scaledOutput', 0, ...
    'ao_laser', 0, 'ao_cellCommand', 1);
end

function [daq, model] = modelBackedDaq()
n = 5;
cells = struct('id', {}, 'scanfieldXY', {}, 'dmdXY', {}, 'layer', {}, ...
    'isOpsinPos', {}, 'score', {}, 'notes', {});
for k = 1:n
    cells(k) = struct('id', k, 'scanfieldXY', [k, k], ...
        'dmdXY', [100 + 40 * k, 300], 'layer', 1, 'isOpsinPos', true, ...
        'score', 1, 'notes', '');
end
targets = struct('version', 1, 'patchedCellId', NaN, 'cells', cells, ...
    'umPerDmdPx', 0.6);
config = struct( ...
    'groundTruth', struct('nCells', n, 'seed', 21, 'opsinNegFraction', 0, ...
        'connectedFraction', 1.0, 'wEMeanPc', 4.0, 'releaseProb', 1.0, ...
        'wIGainPc', 1.0, 'opsinGainMean', 3.0, 'noiseRmsPa', 2, 'noiseRmsMv', 0.2), ...
    'ephys', struct(), ...
    'fov', struct('umPerDmdPx', 0.6), ...
    'ensemble', struct('laserVolts', 2.0));
model = sem.sim.makeGroundTruthNetwork(config, targets);
daq = sem.hardware.MockEphysDAQ();
daq.initialize(basicDaqCfg());
daq.attachNetworkModel(model);
end
