"""Mirror of MATLAB tests/test_units.m — the two files must agree forever."""

import numpy as np
import pytest

from slice_ephys_analysis import units

GAIN = {"commandVcMvPerV": 20, "commandIcPaPerV": 400,
        "scaledVcPaPerV": 1000, "scaledIcMvPerMv": 20}


def test_command_vc_roundtrip():
    assert units.command_cell_to_daq_volts(-70, "VC", GAIN) == pytest.approx(-3.5)
    assert units.command_daq_volts_to_cell(-3.5, "VC", GAIN) == pytest.approx(-70)


def test_command_ic_roundtrip():
    assert units.command_cell_to_daq_volts(-20, "IC", GAIN) == pytest.approx(-0.05)
    assert units.command_daq_volts_to_cell(-0.05, "IC", GAIN) == pytest.approx(-20)


def test_scaled_vc_roundtrip():
    assert units.scaled_daq_volts_to_cell(0.25, "VC", GAIN) == pytest.approx(250)
    assert units.scaled_cell_to_daq_volts(250, "VC", GAIN) == pytest.approx(0.25)


def test_scaled_ic_roundtrip():
    assert units.scaled_daq_volts_to_cell(1.3, "IC", GAIN) == pytest.approx(65)
    assert units.scaled_cell_to_daq_volts(65, "IC", GAIN) == pytest.approx(1.3)


def test_arrays_pass_through():
    v = np.array([0.1, -0.2, 0.3])
    out = units.scaled_daq_volts_to_cell(v, "VC", GAIN)
    assert np.allclose(out, v * 1000)


def test_bad_mode_raises():
    with pytest.raises(ValueError):
        units.scaled_daq_volts_to_cell(1.0, "XX", GAIN)
