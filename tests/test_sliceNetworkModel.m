classdef test_sliceNetworkModel < matlab.unittest.TestCase
    %test_sliceNetworkModel Ground-truth model sign conventions and physics.
    %   The Python analysis assumes: VC at -70 -> evoked E is INWARD
    %   (negative pA); VC at +10 -> evoked I is OUTWARD (positive pA) and E
    %   nearly silent; CC -> depolarizing PSPs and threshold spikes; direct
    %   photostim drive falls off with distance (the ground-truth PPSF).
    %   These are exactly the assertions here.

    methods (Test)
        function epsc_inward_at_minus70(tc)
            [model, ~] = strongModel();
            ev = ensembleEvent(model);
            snip = model.synthesizeEvoked(ev, struct('mode', 'VC', 'holdingMv', -70), ...
                20000, 5000);
            tc.verifyLessThan(min(snip), -5);        % clear inward deflection
            tc.verifyLessThan(sum(snip), 0);         % net negative charge
        end

        function ipsc_outward_at_plus10_e_small(tc)
            [model, ~] = strongModel();
            ev = ensembleEvent(model);
            snip = model.synthesizeEvoked(ev, struct('mode', 'VC', 'holdingMv', 10), ...
                20000, 5000);
            tc.verifyGreaterThan(max(snip), 5);      % clear outward deflection
            tc.verifyGreaterThan(sum(snip), 0);      % net positive charge
        end

        function cc_depolarizes(tc)
            [model, ~] = strongModel();
            ev = ensembleEvent(model);
            snip = model.synthesizeEvoked(ev, struct('mode', 'IC', 'holdingMv', 0), ...
                20000, 5000);
            tc.verifyGreaterThan(max(snip), 0.2);    % depolarizing PSP (mV)
        end

        function direct_drive_falls_off_with_distance(tc)
            [model, targets] = strongModel();
            soma = targets.cells(1).dmdXY;
            evNear = struct('kind', 'direct', 'cellIds', 1, 'fillFractions', 1, ...
                'centroids', soma, 'laserVolts', 2, 'durS', 0.01);
            evFar = evNear;
            evFar.centroids = soma + [80, 0];        % 80 px * 0.6 um/px = 48 um off
            near = model.synthesizeEvoked(evNear, struct('mode', 'VC', 'holdingMv', -70), ...
                20000, 2000);
            far = model.synthesizeEvoked(evFar, struct('mode', 'VC', 'holdingMv', -70), ...
                20000, 2000);
            tc.verifyLessThan(min(near), -100);      % strong photocurrent on soma
            tc.verifyGreaterThan(min(far), min(near) * 0.05);  % >95% attenuated off-soma
        end

        function direct_cc_spikes_at_high_drive(tc)
            [model, targets] = strongModel();
            ev = struct('kind', 'direct', 'cellIds', 1, 'fillFractions', 1, ...
                'centroids', targets.cells(1).dmdXY, 'laserVolts', 4, 'durS', 0.01);
            snip = model.synthesizeEvoked(ev, struct('mode', 'IC', 'holdingMv', 0), ...
                20000, 2000);
            tc.verifyGreaterThan(max(snip), 40);     % AP overshoot rides on the PSP
        end

        function seeded_determinism(tc)
            [m1, t1] = strongModel();
            [m2, t2] = strongModel(); %#ok<ASGLU>
            ev = ensembleEvent(m1);
            s1 = m1.synthesizeEvoked(ev, struct('mode', 'VC', 'holdingMv', -70), 20000, 3000);
            s2 = m2.synthesizeEvoked(ev, struct('mode', 'VC', 'holdingMv', -70), 20000, 3000);
            tc.verifyEqual(s1, s2, 'AbsTol', 1e-12);
            tc.verifyEqual(m1.wE, m2.wE, 'AbsTol', 1e-12);
        end

        function ground_truth_export_shape(tc)
            [model, ~] = strongModel();
            gt = model.exportGroundTruth();
            tc.verifyEqual(numel(gt.W_E_eff), model.nCells);
            tc.verifyEqual(numel(gt.W_I_eff), model.nCells);
            % Opsin-negative cells must have exactly zero effective weight.
            tc.verifyEqual(gt.W_E_eff(gt.opsinGain == 0), ...
                zeros(nnz(gt.opsinGain == 0), 1));
        end
    end
end

% --- Local helpers ---

function [model, targets] = strongModel()
% A small network where cell 1 is strongly connected and strongly driven,
% so sign/threshold assertions are unambiguous.
n = 6;
cells = struct('id', {}, 'scanfieldXY', {}, 'dmdXY', {}, 'layer', {}, ...
    'isOpsinPos', {}, 'score', {}, 'notes', {});
for k = 1:n
    cells(k) = struct('id', k, 'scanfieldXY', [k * 10, k * 20], ...
        'dmdXY', [200 + 30 * k, 300], 'layer', 1, 'isOpsinPos', true, ...
        'score', 1, 'notes', '');
end
targets = struct('version', 1, 'patchedCellId', NaN, 'cells', cells, ...
    'umPerDmdPx', 0.6);
config = struct( ...
    'groundTruth', struct('nCells', n, 'seed', 11, 'opsinNegFraction', 0, ...
        'connectedFraction', 1.0, 'wEMeanPc', 3.0, 'releaseProb', 1.0, ...
        'wIGainPc', 2.0, 'opsinGainMean', 3.0, 'maxSpikesPerPulse', 3, ...
        'noiseRmsPa', 0, 'noiseRmsMv', 0, 'ppsfSigmaUm', 12, ...
        'directPeakPa', 400), ...
    'ephys', struct(), ...
    'fov', struct('umPerDmdPx', 0.6), ...
    'ensemble', struct('laserVolts', 2.0));
model = sem.sim.makeGroundTruthNetwork(config, targets);
end

function ev = ensembleEvent(model)
ids = model.cellIds(1:4);
[~, rows] = ismember(ids, model.cellIds);
ev = struct('kind', 'ensemble', 'cellIds', ids, ...
    'fillFractions', ones(4, 1), ...
    'centroids', model.dmdXY(rows, :), ...
    'laserVolts', 2, 'durS', 0.01);
end
