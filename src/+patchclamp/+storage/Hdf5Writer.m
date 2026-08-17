classdef Hdf5Writer < handle
    % Hdf5Writer  Session-scoped HDF5 writer for patch-clamp trials.
    %
    % Layout (architecture.md sec.7):
    %   /meta/
    %     config              (JSON string)
    %     startTimestamp      (ISO 8601 string)
    %     cellId              (string)
    %   /trials/000000/
    %     aiCellUnits         (N-by-1 double)
    %     aoCommandCellUnits  (N-by-1 double)
    %     aoLedVolts          (N-by-1 double)
    %     rsMohm, riMohm, holding, holdingUnit, mode,
    %       sampleRateHz, timestamp                (attributes)
    %     gainSnapshot/                            (sub-group, gain fields as attrs)
    %
    % Crash safety: each h5create+h5write is its own open/write/close cycle,
    % so the file on disk is always a valid HDF5 between calls. A trial group
    % is considered "committed" only when its aiCellUnits dataset exists; the
    % writer always writes that dataset last, and peekTrialCount() uses this
    % marker. If a process dies mid-appendTrial, the next consumer simply
    % skips the partial group (or peekTrialCount returns the count of fully
    % committed trials).
    %
    % All units are cell units (mV, pA) per claude.md invariant 1. The
    % writer never sees raw DAQ volts.

    properties (SetAccess = private)
        FilePath        (1,1) string
        NextTrialIndex  (1,1) uint32 = uint32(0)
        IsOpen          (1,1) logical = false
    end

    methods
        function obj = Hdf5Writer(filePath, sessionMeta)
            arguments
                filePath    (1,1) string
                sessionMeta (1,1) struct
            end

            if exist(filePath, "file") == 2
                error("patchclamp:storage:FileExists", ...
                    "Refusing to overwrite existing file: %s", filePath);
            end

            parentDir = fileparts(filePath);
            if strlength(parentDir) > 0 && ~isfolder(parentDir)
                mkdir(parentDir);
            end

            if ~isfield(sessionMeta, "cellId")
                error("patchclamp:storage:MissingField", ...
                    "sessionMeta must contain field 'cellId'.");
            end
            if ~isfield(sessionMeta, "config")
                error("patchclamp:storage:MissingField", ...
                    "sessionMeta must contain field 'config'.");
            end

            cellId = string(sessionMeta.cellId);
            configJson = string(jsonencode(sessionMeta.config));
            startTimestamp = string(datetime("now", ...
                "TimeZone", "local", "Format", "yyyy-MM-dd'T'HH:mm:ssXXX"));

            obj.FilePath = filePath;

            obj.writeStringScalar("/meta/config", configJson);
            obj.writeStringScalar("/meta/startTimestamp", startTimestamp);
            obj.writeStringScalar("/meta/cellId", cellId);

            % Persist any other scalar-string meta fields under /meta/<name>
            % so the file is self-describing.
            extras = setdiff(string(fieldnames(sessionMeta)), ["cellId", "config"]);
            for k = 1:numel(extras)
                f = extras(k);
                val = sessionMeta.(f);
                if (isstring(val) || ischar(val)) && isscalar(string(val))
                    obj.writeStringScalar("/meta/" + f, string(val));
                end
            end

            obj.NextTrialIndex = uint32(0);
            obj.IsOpen = true;
        end

        function appendTrial(obj, trialResult)
            arguments
                obj
                trialResult (1,1) struct
            end

            if ~obj.IsOpen
                error("patchclamp:storage:NotOpen", ...
                    "Writer is closed; cannot append.");
            end

            idx = obj.NextTrialIndex;
            group = sprintf("/trials/%06u", idx);

            % Advance counter *before* writing, per contract: do not roll
            % back on partial write. Next append goes to a fresh index.
            obj.NextTrialIndex = idx + uint32(1);

            % h5writeatt does not create missing groups, so we create the
            % trial group and its gainSnapshot sub-group explicitly first.
            obj.ensureGroup("/trials");
            obj.ensureGroup(group);
            obj.ensureGroup(group + "/gainSnapshot");

            % Numeric attributes (parent group is guaranteed to exist).
            obj.writeNumAttr(group, "rsMohm",       obj.getField(trialResult, "rsMohm",       NaN));
            obj.writeNumAttr(group, "riMohm",       obj.getField(trialResult, "riMohm",       NaN));
            obj.writeNumAttr(group, "holding",      obj.getField(trialResult, "holding",      NaN));
            obj.writeNumAttr(group, "sampleRateHz", obj.getField(trialResult, "sampleRateHz", NaN));

            % String attributes.
            obj.writeStrAttr(group, "mode",        string(obj.getField(trialResult, "mode",        "")));
            obj.writeStrAttr(group, "holdingUnit", string(obj.getField(trialResult, "holdingUnit", "")));
            obj.writeStrAttr(group, "timestamp",   string(obj.getField(trialResult, "timestamp",   "")));

            % Gain snapshot as a sub-group with the four canonical attrs.
            gain = obj.getField(trialResult, "gainSnapshot", struct());
            gainGroup = group + "/gainSnapshot";
            gainFields = ["commandVcMvPerV", "commandIcPaPerV", "scaledVcPaPerV", "scaledIcMvPerMv"];
            for k = 1:numel(gainFields)
                f = gainFields(k);
                if isfield(gain, f)
                    obj.writeNumAttr(gainGroup, f, double(gain.(f)));
                end
            end

            % Waveform datasets. Write aiCellUnits LAST so its presence is
            % the atomic "trial committed" marker for crash-recovery.
            ao = obj.getField(trialResult, "aoCommandCellUnits", []);
            if ~isempty(ao)
                obj.writeDoubleColumn(group + "/aoCommandCellUnits", double(ao(:)));
            end
            led = obj.getField(trialResult, "aoLedVolts", []);
            if ~isempty(led)
                obj.writeDoubleColumn(group + "/aoLedVolts", double(led(:)));
            end
            ai = obj.getField(trialResult, "aiCellUnits", []);
            if ~isempty(ai)
                obj.writeDoubleColumn(group + "/aiCellUnits", double(ai(:)));
            end
        end

        function close(obj)
            % Idempotent. h5* calls flush per-call; nothing to release.
            obj.IsOpen = false;
        end

        function delete(obj)
            if obj.IsOpen
                obj.close();
            end
        end
    end

    methods (Access = private)
        function writeDoubleColumn(obj, datasetPath, vec)
            h5create(obj.FilePath, char(datasetPath), size(vec), "Datatype", "double");
            h5write(obj.FilePath, char(datasetPath), vec);
        end

        function writeStringScalar(obj, datasetPath, value)
            % Scalar string dataset (MATLAB R2023a+ supports Datatype='string').
            h5create(obj.FilePath, char(datasetPath), 1, "Datatype", "string");
            h5write(obj.FilePath, char(datasetPath), string(value));
        end

        function writeNumAttr(obj, objectPath, attrName, value)
            h5writeatt(obj.FilePath, char(objectPath), char(attrName), double(value));
        end

        function writeStrAttr(obj, objectPath, attrName, value)
            h5writeatt(obj.FilePath, char(objectPath), char(attrName), char(value));
        end

        function ensureGroup(obj, groupPath)
            % Create groupPath (and any missing ancestors) if absent. Uses
            % low-level H5G because h5create requires a dataset and there's
            % no group-level equivalent.
            fid = H5F.open(obj.FilePath, "H5F_ACC_RDWR", "H5P_DEFAULT");
            cleanupFid = onCleanup(@() H5F.close(fid));

            parts = split(string(groupPath), "/");
            parts = parts(parts ~= "");
            currentPath = "";
            for k = 1:numel(parts)
                currentPath = currentPath + "/" + parts(k);
                exists = false;
                try
                    exists = logical(H5L.exists(fid, char(currentPath), "H5P_DEFAULT"));
                catch
                    exists = false;
                end
                if ~exists
                    gid = H5G.create(fid, char(currentPath), ...
                        "H5P_DEFAULT", "H5P_DEFAULT", "H5P_DEFAULT");
                    H5G.close(gid);
                end
            end
        end
    end

    methods (Static)
        function trialCount = peekTrialCount(filePath)
            % peekTrialCount  Count /trials/* groups that contain aiCellUnits.
            % Used both by tests and (in R5) by crash-recovery to resume an
            % interrupted session.
            arguments
                filePath (1,1) string
            end
            trialCount = uint32(0);
            if exist(filePath, "file") ~= 2
                return;
            end
            try
                info = h5info(filePath, "/trials");
            catch
                return;  % no /trials group yet
            end
            for k = 1:numel(info.Groups)
                g = info.Groups(k);
                hasAi = false;
                for j = 1:numel(g.Datasets)
                    if string(g.Datasets(j).Name) == "aiCellUnits"
                        hasAi = true; break;
                    end
                end
                if hasAi
                    trialCount = trialCount + uint32(1);
                end
            end
        end

        function v = getField(s, name, default)
            if isfield(s, name)
                v = s.(name);
            else
                v = default;
            end
        end
    end
end
