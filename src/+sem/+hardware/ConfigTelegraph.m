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
        CurrentHoldingMv (1,1) double = 0
        HoldingIsKnown (1,1) logical = false
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
            obj.CurrentHoldingMv = sem.util.configField(eCfg, 'holdingVcEMv', -70);
        end

        function mode = getMode(obj)
            mode = obj.CurrentMode;
        end

        function gainStruct = getGain(obj)
            gainStruct = obj.CurrentGain;
        end

        function holdingMv = getHolding(obj)
            %getHolding The holding the amplifier is applying, in cell units.
            %
            %   STAND-IN. With a real MccTelegraph this reads the Commander over
            %   the AxMultiClampMsg link, which is the point: the experimenter
            %   sets holding on the front panel and software only reports it.
            %   Here there is no link, so this returns the last value software
            %   was told about (config default, or whatever setHolding wrote).
            %
            %   isHoldingKnown() says which of those you are getting, so the GUI
            %   can show a read value differently from an assumed one instead of
            %   presenting a guess as a measurement.
            holdingMv = obj.CurrentHoldingMv;
        end

        function tf = isHoldingKnown(obj)
            %isHoldingKnown True once holding came from a read or an explicit set.
            tf = obj.HoldingIsKnown;
        end

        function setHolding(obj, holdingMv)
            %setHolding Command a new holding level (explicit operator request).
            %   On the real rig this writes the Commander. Never called
            %   implicitly: sweeps leave holding alone unless the operator
            %   pressed one of the holding buttons.
            if ~isnumeric(holdingMv) || ~isscalar(holdingMv) || ~isfinite(holdingMv)
                error('sem:hardware:ConfigTelegraph:badHolding', ...
                    'holdingMv must be a finite scalar.');
            end
            changed = ~obj.HoldingIsKnown || obj.CurrentHoldingMv ~= holdingMv;
            obj.CurrentHoldingMv = double(holdingMv);
            obj.HoldingIsKnown = true;
            if changed
                notify(obj, 'HoldingChanged');
            end
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
