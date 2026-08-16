"""Cell-unit <-> DAQ-volt conversions. Python mirror of sem.util.Units.

This module and MATLAB's sem/util/Units.m implement the same contract —
change them together. Raw aiData is saved in DAQ VOLTS; every conversion to
pA/mV happens here, using the per-trial gains snapshot from
metadata.ephys.gains (single source of truth).

Gain struct fields:
  commandVcMvPerV   DAQ AO -> 700B EXT COMMAND, VC (physical constant, 20)
  commandIcPaPerV   DAQ AO -> 700B EXT COMMAND, IC (physical constant, 400)
  scaledVcPaPerV    700B SCALED OUTPUT -> DAQ AI, VC (front panel, typ. 1000)
  scaledIcMvPerMv   700B SCALED OUTPUT -> DAQ AI, IC (front panel, typ. 20)
"""

from __future__ import annotations

import numpy as np


def _check_mode(mode: str) -> str:
    if mode not in ("VC", "IC"):
        raise ValueError(f"mode must be 'VC' or 'IC'; got {mode!r}")
    return mode


def scaled_daq_volts_to_cell(volts, mode: str, gain: dict):
    """AI sample (DAQ volts) -> cell units (pA in VC, mV in IC)."""
    _check_mode(mode)
    v = np.asarray(volts, dtype=float)
    if mode == "VC":
        return v * float(gain["scaledVcPaPerV"])
    return v * (1000.0 / float(gain["scaledIcMvPerMv"]))


def scaled_cell_to_daq_volts(cell_value, mode: str, gain: dict):
    """Inverse of scaled_daq_volts_to_cell."""
    _check_mode(mode)
    c = np.asarray(cell_value, dtype=float)
    if mode == "VC":
        return c / float(gain["scaledVcPaPerV"])
    return c * (float(gain["scaledIcMvPerMv"]) / 1000.0)


def command_cell_to_daq_volts(cell_value, mode: str, gain: dict):
    """Command in cell units (mV in VC, pA in IC) -> DAQ AO volts."""
    _check_mode(mode)
    c = np.asarray(cell_value, dtype=float)
    if mode == "VC":
        return c / float(gain["commandVcMvPerV"])
    return c / float(gain["commandIcPaPerV"])


def command_daq_volts_to_cell(volts, mode: str, gain: dict):
    """Inverse of command_cell_to_daq_volts."""
    _check_mode(mode)
    v = np.asarray(volts, dtype=float)
    if mode == "VC":
        return v * float(gain["commandVcMvPerV"])
    return v * float(gain["commandIcPaPerV"])
