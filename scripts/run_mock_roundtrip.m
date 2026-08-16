%run_mock_roundtrip The two-step end-to-end validation, documented as one file.
%   Step 1 (MATLAB, this script): generate the seeded mock session.
%   Step 2 (Python, run from a terminal): recover the ground-truth weights.
%
%       cd analysis
%       .venv/bin/python -m pytest tests/test_mock_roundtrip.py -v
%
%   Pass criteria (asserted by the pytest): r(W_E) >= 0.9 on connected
%   cells, r(W_I) >= 0.8, opsin-/unconnected cells under the permutation
%   null, cv R^2 > 0.

thisDir = fileparts(mfilename('fullpath'));
run(fullfile(thisDir, 'run_mock_session.m'));
