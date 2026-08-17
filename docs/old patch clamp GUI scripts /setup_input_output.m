
function setup_input_output (~)

% create input, output and timebase vectors

global cell1 cell2 LED Ramp ExpStruct Exp_Defaults motor

LEDoutput=ExpStruct.LEDoutput; sweepduration=Exp_Defaults.sweepduration;


% set initial values for the LED output here
pulseamp=1; % in volts 
pulseamp2=1.5; % in volts for second analog output control 
pulseduration=750; % in milliseconds
pulsenumber=1;
pulsefrequency=10; % in Hz
pulse_starttime=750; % in milleseconds
rampstart_voltage=3; % in volts
rampend_voltage=4; % in volts
ramp_duration=600; % in milliseconds
ramp_frequency=5; % in Hz
ramp_number=1;     
rampstart_time=200;  % in milleseconds
rampend_time=800; % in milleseconds

DCoffset1 = 0; % use for applying DC offset for devices requiring negative holding voltages
DCoffset2 = 0;


%% untab for visual cortex experiment
% pulse_starttime=500; % in milleseconds
% Exp_Defaults.sweepduration = 1 ;
% Exp_Defaults.DIO_on = 1;
% pulseduration=500; % in milliseconds
% pulsenumber=3 ;
% pulsefrequency=0.2083; % in Hz
% Exp_Defaults.sweepduration =10;


%% set default xlimits for measuring charge here
if (Exp_Defaults.DIO_on == 1 ) % if visual stim
    ExpStruct.TuningStruct.leftmeasure=0.5; 
    ExpStruct.TuningStruct.rightmeasure=1;
else
    ExpStruct.TuningStruct.leftmeasure=.5; 
    ExpStruct.TuningStruct.rightmeasure=1.0;
end

%% make LED and timebase vectors
ExpStruct.LEDoutput= makepulseoutputs(pulse_starttime, pulsenumber, pulseduration, pulseamp ,pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.LEDoutput2= makepulseoutputs(pulse_starttime, pulsenumber, pulseduration, pulseamp ,pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.timebase=linspace(0,Exp_Defaults.sweepduration,(Exp_Defaults.Fs*Exp_Defaults.sweepduration));
ExpStruct.shutterTriggerOutput= makepulseoutputs(pulse_starttime, pulsenumber, pulseduration, 1 ,pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);

% setup motor pulses
motor_fixed_pulses=450;
motorpulsenumber=450;
motorpulsefrequency=7500;
motorpulseamplitude=5;
motorpulseduration=0.03;
motorpulsestarttime=300;


motorpulses = makemotorpulses(motorpulsestarttime, motorpulsenumber, motorpulseduration, motorpulseamplitude, motorpulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
motorpulsestarttime=1000;
temp=motorpulses;
motorpulses = makemotorpulses(motorpulsestarttime, motorpulsenumber, motorpulseduration, motorpulseamplitude, motorpulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.motorpulses=temp+motorpulses;


% setup motor direction 
ExpStruct.motordir = makepulseoutputs(650, 1, 600, 5, 1, Exp_Defaults.Fs, Exp_Defaults.sweepduration); 

% setup testpulse for votlage clamp
ExpStruct.testpulse = makepulseoutputs(50,1, 50, -0.2, 1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);

% setup current injection params for cell1
ccpulseamp1= 2000;
ccpulse_dur1=10;
ccnumpulses1=1;
ccpulsefreq1=1000;
ccpulsestarttime1=1;
deltacurrentpulseamp1=0;
if strcmp(Exp_Defaults.amplifier, 'axopatch200B')
    externalcommandsensitivity = 2000;
else
  externalcommandsensitivity = 400;% for Multiclamp
end
ExpStruct.CCoutput1=makepulseoutputs(ccpulsestarttime1,ccnumpulses1, ccpulse_dur1, ccpulseamp1, ccpulsefreq1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.CCoutput1=ExpStruct.CCoutput1/externalcommandsensitivity; % scale by externalcommand sensitivity under Current clamp

% setup current injection params for cell2
ccpulseamp2=0.01;
ccpulse_dur2=0.01;
ccnumpulses2=1;
ccpulsefreq2=3000;
ccpulsestarttime2=1500;
deltacurrentpulseamp2=100;
ExpStruct.CCoutput2=makepulseoutputs(ccpulsestarttime2,ccnumpulses2, ccpulse_dur2, ccpulseamp2, ccpulsefreq2, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.CCoutput2=ExpStruct.CCoutput2/externalcommandsensitivity; % scale by externalcommand sensitivity under Current clamp
% ExpStruct.piezooutput=makecosineoutputs(ccpulsestarttime1,ccnumpulses1, ccpulse_dur1, ccpulseamp1, ccpulsefreq1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);

% delta param
ExpStruct.deltaparam=0;

% user gains

user_gain = 1; % set gains according to Multiclamp. 1V/nA default setting for voltage clamp, 20mV/mV for Iclamp
user_gain2 = 1;

highpass_freq1=500;
highpass_freq2=500;

series_r1=[];
holding_i1=[];
input_r1=[];
spikerate1=[];

series_r2=[];
holding_i2=[];
input_r2=[];


cell1 = struct('series_r', series_r1, 'holding_i', holding_i1, 'input_r', input_r1, 'pulseamp', ...
    ccpulseamp1, 'pulseduration', ccpulse_dur1, 'pulsenumber', ccnumpulses1, 'pulsefrequency', ccpulsefreq1, ...
    'pulse_starttime', ccpulsestarttime1, 'deltacurrentpulseamp', deltacurrentpulseamp1, 'user_gain', user_gain, ...
    'highpass_freq', highpass_freq1, 'spikerate1', spikerate1, 'externalcommandsensitivity', externalcommandsensitivity);

cell2 = struct('series_r', series_r2, 'holding_i', holding_i2, 'input_r', input_r2, 'pulseamp', ...
    ccpulseamp2, 'pulseduration', ccpulse_dur2, 'pulsenumber', ccnumpulses2, 'pulsefrequency', ccpulsefreq2, ...
    'pulse_starttime', ccpulsestarttime2, 'deltacurrentpulseamp', deltacurrentpulseamp2,'user_gain', user_gain2, ...
    'highpass_freq', highpass_freq2);

LED = struct('pulseamp', pulseamp, 'pulseamp2', pulseamp2, 'pulseduration', pulseduration, 'pulsefrequency', pulsefrequency, ...
    'pulsenumber', pulsenumber, 'pulse_starttime', pulse_starttime, 'DCoffset1', DCoffset1, 'DCoffset2', DCoffset2);

% initizalize Lumencor vectors
LED.color = 4;
LED.intensity = 0; % initialize Lumencor output intensity to 10% if using
ExpStruct.Lumencor_output = Digital_outputgen( LED.color , LED.pulse_starttime, LED.pulsenumber, LED.pulseduration, LED.pulsefrequency );
% ExpStruct.Lumencor_output(:,1)=makepulseoutputs(pulse_starttime-5, pulsenumber, pulseduration+5, 1 ,pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.Lumencor_output = ones(length(ExpStruct.timebase), 6);
% set default condition for digital line on port 7
ExpStruct.digitalLED_on = 0;
ExpStruct.digitalLEDoutput = makepulseoutputs(pulse_starttime, pulsenumber, pulseduration, ExpStruct.digitalLED_on ,pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
% openLumencor;
% set_lumencor_intensity(10, LED.color);

%% generate galvo vectors
[ ExpStruct.galvoxOutput, ExpStruct.galvoyOutput ] = updateGalvoVectors(pulse_starttime, pulsenumber, pulseduration, 1 ,pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);


% make sweep trigger vector for external triggering
ExpStruct.sweepTrigger = makepulseoutputs(150, 1, 5, 1 ,1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);


Ramp = struct('rampend_time', rampend_time, 'rampend_voltage', rampend_voltage, 'rampstart_time', rampstart_time, 'rampstart_voltage', rampstart_voltage, ...
                'ramp_duration', ramp_duration, 'ramp_frequency', ramp_frequency, 'ramp_number', ramp_number);

motor=struct('pulsenumber', motorpulsenumber, 'pulsefrequency', motorpulsefrequency, 'pulseamp', motorpulseamplitude, ...
    'pulseduration', motorpulseduration, 'pulse_starttime', motorpulsestarttime, 'fixed_pulses', motor_fixed_pulses); 
