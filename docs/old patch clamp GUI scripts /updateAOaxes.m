

global h ExpStruct Exp_Defaults cell1

val1=get(h.Lumencor_check, 'Value');
val2=get(h.spectrum_check, 'Value');

if val1 == 0 % if Lumencor is being used don't plot LEDoutput
    plot(h.LEDoutput_axes, ExpStruct.timebase,ExpStruct.LEDoutput,'r', ExpStruct.timebase,-1*ExpStruct.LEDoutput2,'b', ExpStruct.timebase, ExpStruct.digitalLEDoutput, 'g');%,ExpStruct.timebase, ExpStruct.piezooutput); 
   ylim(h.LEDoutput_axes, [-5 4]); 
%    hold on;
end
% axis(h.LEDoutput_axes, [0 Exp_Defaults.sweepduration -6  6])
% axis(h.LEDoutput_axes, [0 Exp_Defaults.sweepduration -1  max(ExpStruct.LEDoutput)])

if (val1+val2>0)
    plot(h.LEDoutput_axes,ExpStruct.timebase, ExpStruct.Lumencor_output);
    set(h.LEDoutput_axes, 'YLIM', [0 1]);
end
    xlabel(h.LEDoutput_axes, 'seconds')
ylabel(h.LEDoutput_axes, 'V')

currentCCoutput1=ExpStruct.CCoutput1*cell1.externalcommandsensitivity;
if isempty(ExpStruct.CCoutput2)~=1
    currentCCoutput2=ExpStruct.CCoutput2*Exp_Defaults.CCexternalcommandsensitivity; % reverse scale just for plotting
    plot(h.CCoutput_axes,ExpStruct.timebase,currentCCoutput1,ExpStruct.timebase,currentCCoutput2);
elseif isempty(ExpStruct.CCoutput1)~=1
    plot(h.CCoutput_axes,ExpStruct.timebase,currentCCoutput1);

    
end

%% plot galvo vectors if using


    if max(currentCCoutput1)>600
    axis(h.CCoutput_axes, [0 Exp_Defaults.sweepduration -200 1.1*max(currentCCoutput1)]);
else
    axis(h.CCoutput_axes, [0 Exp_Defaults.sweepduration -200 600]);
end
xlabel(h.CCoutput_axes, 'seconds')
if   get(h.Cell1_type_popup,'Value') == 1 % Voltage clamp
    ylabel(h.CCoutput_axes, 'mV')
else % current clamp
    ylabel(h.CCoutput_axes, 'pA')
end
    
if get(h.galvosCheck, 'Value')
%     plot(h.LEDoutput_axes, ExpStruct.timebase,ExpStruct.shutterTriggerOutput,'c', ExpStruct.timebase,ExpStruct.LEDoutput, ExpStruct.timebase,ExpStruct.LEDoutput2,'r', ExpStruct.timebase, ExpStruct.digitalLEDoutput, 'g')
    plot(h.CCoutput_axes, ExpStruct.timebase, ExpStruct.galvoxOutput, 'b', ExpStruct.timebase, ExpStruct.galvoyOutput);
    ylabel('V');
%hold off;
end
    % axis(h.CCoutput_axes, [0 Exp_Defaults.sweepduration -6  6])
ExpStruct.testpulse = makepulseoutputs(50,1, 50, -0.2, 1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);

    