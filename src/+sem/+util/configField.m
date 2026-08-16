function value = configField(s, name, default)
%configField Read a config struct field with a fallback default.
%   value = sem.util.configField(s, name, default) returns s.(name) when the
%   field exists, otherwise default. The standard config-read helper (same
%   contract as the DMD repo's local configField copies, promoted to a
%   package function here because every sem module needs it).
if isstruct(s) && isfield(s, name)
    value = s.(name);
else
    value = default;
end
end
