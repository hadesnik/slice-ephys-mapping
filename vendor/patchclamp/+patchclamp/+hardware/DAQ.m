classdef (Abstract) DAQ < handle
    % DAQ  Abstract interface for a hardware-timed analog I/O backend.
    %
    % Concrete implementations:
    %   patchclamp.hardware.NidaqBackend  (real NI-DAQmx via Data Acquisition Toolbox; Windows-only)
    %   patchclamp.hardware.FakeBackend   (synthesises RC traces for macOS dev/test)
    %
    % Contract:
    %   - configureTrial() and run() exchange waveforms in CELL UNITS (mV/pA) on the
    %     amplifier-command and amplifier-readback lines. The backend is responsible
    %     for converting to/from raw DAQ volts using the live telegraph gain. The LED
    %     line is the exception: it uses raw volts because there is no amplifier in
    %     that path.
    %   - AO and AI share a single sample clock and are triggered together so they are
    %     sample-aligned (architecture.md invariant 2).
    %   - run() blocks until the AI buffer is full, then returns the converted samples.
    %     Each trial is a self-contained finite task (claude.md invariant 4).

    methods (Abstract)
        configureTrial(obj, ao0CommandCellUnits, ao2LedVolts, aiChannelName, sampleRateHz, durationSec)
            % Configure the next finite-acquisition trial.
            %
            % ao0CommandCellUnits : double vector, command waveform in CELL UNITS
            %                      (mV in VC, pA in IC). Backend converts to DAQ volts
            %                      using the current telegraph gain. Length must equal
            %                      sampleRateHz*durationSec.
            % ao2LedVolts         : double vector, LED command in raw VOLTS (0..5).
            %                      Same length as ao0.
            % aiChannelName       : string, e.g. "ai1".
            % sampleRateHz        : positive integer.
            % durationSec         : positive scalar.

        aiSamplesCellUnits = run(obj)
            % Arm AO+AI on the shared sample clock, trigger them together, block
            % until the AI buffer is full, return the AI samples already converted
            % to cell units (pA in VC, mV in IC) using the telegraph gain that was
            % active at trial start.

        cleanup(obj)
            % Release DAQ resources. Safe to call repeatedly.
    end
end
