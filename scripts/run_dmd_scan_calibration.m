%run_dmd_scan_calibration DMD -> ScanImage scan-field affine (Phase B).
%   The slice targeting pipeline maps segmented 2p centroids into DMD pixels
%   through inv(dmdToScan_affine). That affine comes from the DMD repo's
%   two-step calibration (its CLAUDE.md, "Two-step spatial calibration
%   procedure"):
%
%     Step A  tfp.calibration.alignDMDtoCamera       DMD spots -> camera
%     Step B  tfp.calibration.crossRegisterScanImage scan field -> camera
%     Compose dmdToScan_affine = inv(scanToCam_affine) * dmdToCam_affine
%     Verify  project a DMD spot, mROI-scan its predicted position, flip
%             scan_fast/slow_axis_sign until centered.
%
%   This script is the sem-side pointer to that procedure, not a
%   reimplementation: follow the DMD repo's docs/BRINGUP_GUIDE.md on this
%   rig, save the calibration with tfp.io.saveCalibration, then set
%   calibration_file in configs/slice_rig.yaml to the saved path.
%
%   After calibration, scripts/run_targeting.m consumes it.

fprintf(['run_dmd_scan_calibration:\n' ...
    '  Follow the DMD repo''s two-step calibration on this rig (see the\n' ...
    '  "Two-step spatial calibration procedure" in its CLAUDE.md and\n' ...
    '  docs/BRINGUP_GUIDE.md), then:\n' ...
    '    calib = ...  %% struct with dmdToScan_affine (3x3)\n' ...
    '    tfp.io.saveCalibration(calib, ''dmd_scan'', config)\n' ...
    '  and point calibration_file in configs/slice_rig.yaml at the file.\n']);
