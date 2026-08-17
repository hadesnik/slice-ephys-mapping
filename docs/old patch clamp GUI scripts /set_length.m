

function set_length(newDuration)

global Exp_Defaults ExpStruct LED cell1 cell2 motor 
Exp_Defaults.sweepduration=newDuration;

ExpStruct.timebase=linspace(0,Exp_Defaults.sweepduration,(Exp_Defaults.Fs*Exp_Defaults.sweepduration));
if ExpStruct.pulsesorramps==0
    ExpStruct.LEDoutput = makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
elseif ExpStruct.pulsesorramps==1
    make_ramp_output
else
    ExpStruct.LEDoutput = makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
    pulses=ExpStruct.LEDoutput;
    make_ramp_output
    LEDoutput=ExpStruct.LEDoutput+pulses;
    ExpStruct.LEDoutput=LEDoutput;
end
% 
ExpStruct.CCoutput1=makepulseoutputs(cell1.pulse_starttime,cell1.pulsenumber, cell1.pulseduration, cell1.pulseamp, cell1.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.CCoutput2=makepulseoutputs(cell2.pulse_starttime,cell2.pulsenumber, cell2.pulseduration, cell2.pulseamp, cell2.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.CCoutput1=ExpStruct.CCoutput1/Exp_Defaults.CCexternalcommandsensitivity;
ExpStruct.CCoutput2=ExpStruct.CCoutput2/Exp_Defaults.CCexternalcommandsensitivity;
ExpStruct.testpulse = makepulseoutputs(50,1, 50, -0.2, 1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);

pulse_starttime=1000;
motorpulses = makepulseoutputs(pulse_starttime, motor.pulsenumber, motor.pulseduration, motor.pulseamp, motor.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
pulse_starttime=3000;
temp=motorpulses;
motorpulses = makepulseoutputs(pulse_starttime, motor.pulsenumber, motor.pulseduration, motor.pulseamp, motor.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.motorpulses=temp+motorpulses;
ExpStruct.motordir = makepulseoutputs(2500, 1, 1000, 5, 1, Exp_Defaults.Fs, Exp_Defaults.sweepduration); 
ExpStruct.Lumencor_output = Digital_outputgen( LED.color , LED.pulse_starttime, LED.pulseduration );
updateAOaxes
end
