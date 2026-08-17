classdef ConfigTelegraph < patchclamp.hardware.MultiClamp
    %ConfigTelegraph MultiClamp telegraph sourced from the rig config, not a DLL.
    %
    %   The GUI layer expects a patchclamp.hardware.MultiClamp to tell it the
    %   amplifier's clamp mode and gains. This rig has no telegraph link yet (the
    %   MCC AxMultiClampMsg DLL reader was never written), and sem's gains come
    %   from config.ephys — the same snapshot that lands in every trial's
    %   metadata.ephys.gains. This class presents those config gains through the
    %   telegraph interface so the GUI needs no special case.
    %
    %   Difference from the real thing, stated plainly: the amplifier does NOT
    %   own the mode here. The operator declares it in the GUI and is responsible
    %   for setting the MultiClamp Commander to match — the same operator
    %   contract sem.protocol.EpisodicRunner's block-start prompt already
    %   assumes. setMode is therefore public and writable, whereas against a real
    %   telegraph the GUI's mode control would be a read-only mirror.
    %
    %   When an MccTelegraph is written it drops in as a third MultiClamp
    %   subclass with no GUI change.
    %
    %   Mode/gain setters fire ModeChanged / GainChanged only on an actual
    %   transition, matching patchclamp.hardware.FakeTelegraph so listeners can
    %   de-bounce trivially. Listeners read the new value off the source via
    %   getMode() / getGain() (notify is synchronous).
    %
    %   See also sem.hardware.PatchDaqAdapter, sem.util.Units.gainFromConfig.

    properties (Access = private)
        CurrentMode (1,1) string
        CurrentGain (1,1) struct
    end

    methods
        function obj = ConfigTelegraph(config, initialMode)
            %ConfigTelegraph Build from a sem config struct.
            %   obj = sem.hardware.ConfigTelegraph(config)
            %   obj = sem.hardware.ConfigTelegraph(config, 'IC')
            if nargin < 2 || isempty(initialMode)
                initialMode = 'VC';
            end
            modeC = char(initialMode);
            if ~ismember(modeC, {'VC', 'IC'})
                error('sem:hardware:ConfigTelegraph:badMode', ...
                    'mode must be ''VC'' or ''IC''; got ''%s''.', modeC);
            end
            eCfg = sem.util.configField(config, 'ephys', struct());
            obj.CurrentGain = sem.util.Units.gainFromConfig(eCfg);
            obj.CurrentMode = string(modeC);
        end

        function mode = getMode(obj)
            mode = obj.CurrentMode;
        end

        function gainStruct = getGain(obj)
            gainStruct = obj.CurrentGain;
        end

        function start(~)
            % No-op: there is nothing to poll without a telegraph link.
        end

        function stop(~)
            % No-op.
        end

        function setMode(obj, newMode)
            %setMode Declare the mode the operator has set on the Commander.
            modeC = char(newMode);
            if ~ismember(modeC, {'VC', 'IC'})
                error('sem:hardware:ConfigTelegraph:badMode', ...
                    'mode must be ''VC'' or ''IC''; got ''%s''.', modeC);
            end
            if strcmp(modeC, char(obj.CurrentMode))
                return
            end
            obj.CurrentMode = string(modeC);
            notify(obj, 'ModeChanged');
        end

        function setGain(obj, newGain)
            %setGain Override the config gains (e.g. operator changed the front panel).
            patchclamp.hardware.FakeTelegraph.validateGain(newGain);
            if isequal(newGain, obj.CurrentGain)
                return
            end
            obj.CurrentGain = newGain;
            notify(obj, 'GainChanged');
        end
    end
end
