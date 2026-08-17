function app = runApp(options)
    % runApp  Entry point for the patch-clamp acquisition GUI.
    %
    % Constructs a default FakeBackend + FakeTelegraph and (unless
    % NoStorage=true) opens an HDF5 session file under ~/Documents/PatchData/
    % named after the cell ID + timestamp. Returns the MainWindow handle so
    % the caller can keep it alive in their workspace.
    %
    % On the dev Mac (no NI hardware, no MultiClamp DLL) this is the only
    % entry point that works end-to-end. R4 will add a Windows-only branch
    % that swaps in NidaqBackend + MccTelegraph; that branch must be gated
    % by ispc() so this function continues to work on macOS.
    %
    % Name-value options:
    %   Visible    "on" (default) or "off". Tests pass "off".
    %   NoStorage  true to skip the HDF5 writer (default false; tests use true).
    %   CellId     defaults to "cell-<yyyymmdd-HHMMSS>".
    arguments
        options.Visible   (1,1) string  = "on"
        options.NoStorage (1,1) logical = false
        options.CellId    (1,1) string  = ""
    end

    cellId = options.CellId;
    if strlength(cellId) == 0
        cellId = "cell-" + string(datetime("now", "Format", "yyyyMMdd-HHmmss"));
    end

    config = patchclamp.config.TrialConfig.defaultConfig();
    config.cellId = cellId;

    telegraph = patchclamp.hardware.FakeTelegraph();
    daq       = patchclamp.hardware.FakeBackend(telegraph);

    if options.NoStorage
        writer = [];
    else
        homeDir = string(getenv("HOME"));
        dataDir = fullfile(homeDir, "Documents", "PatchData", ...
                           string(datetime("now", "Format", "yyyy-MM-dd")));
        if exist(dataDir, "dir") ~= 7
            mkdir(dataDir);
        end
        filePath = fullfile(dataDir, cellId + "_" + ...
                            string(datetime("now", "Format", "HHmmss")) + ".h5");
        writer = patchclamp.storage.Hdf5Writer(filePath, ...
                     struct("cellId", cellId, "config", config));
    end

    app = patchclamp.gui.MainWindow( ...
        Daq=daq, Telegraph=telegraph, Writer=writer, Config=config, ...
        Visible=options.Visible);
end
