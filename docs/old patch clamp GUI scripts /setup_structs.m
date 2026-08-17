
function setup_structs (~)
global Exp_Defaults ExpStruct LED Ramp cell1 cell2 globalTimer s 


%%--set Rig Defaults Values here----%%

% set default path for saving files here
SavePath='C:\data\Hillel\';

% set amplifier info
amplifier = 'Multiclamp'; % or Multiclamp

% set sampling frequency in Hz
Fs = 20000;  

% set default inter-stimulus-interval; this is the total time between
% successive trigers from the timer fcn, not the time between trials
ISI = 5;

demoDAQ = Exp_Defaults.demoDAQ;

% set default sweep duration (in seconds)
sweepduration = 2;

% set default state of external triggering, 0 for internal, 1 for external triggering
ExternalTrigger = 0; 

% set default state for saving after each trial, 0 for no saving, 1 for saving after each trial
% may want no saving if will hang up computer on long experiments with long
% trial durations
ifsave=0; 
     
% set total sweeps (usehigh number so timer function doensn't stop)
total_sweeps=1500; 

% set default voltage clamp external command sensititivty (fixed for Axon
% amplifiers at 20 mV/mV)
VCexternalcommandsensitivity = 20; 

% set default type of output for each analog output channel
% AO0='LEDoutput'; 
AO0='wholecell'; 
AO1='LEDoutput';
% AO1 = 'galvox';
AO2='LEDoutput2';
% AO3='LEDoutput2'; 
AO3 = 'LEDoutput';
% set whether using analog input lines 33,34, and 35 for reading digital
% input
DIO_on = 1; % set to 1 for using digital input, otherwise set to 0

% set whether using Lumencor Spectra on digital output lines 1:6
Lumencor_on = 0; % set 1 for using spectra, 0 otherwise

%%--end setting Rig Defaults Values----%%

if Exp_Defaults.demoDAQ~=1
% get info about DAQ device 
device=daq.getDevices;
% daqModel = device.Model;
% NIDAQ_type = strcmp(daqModel,'PCI-6036E');
end
%initialize sweep counter to 1
sweep_counter = 1; 

if strcmp(amplifier,'axopatch200B')==1
    CCexternalcommandsensitivity = 2000; % for axopatch
else
    CCexternalcommandsensitivity = 400;  % for multiclamp
end

%% for old DAQs
% if (NIDAQ_type==1)
%     Fs = 5000; % sampling frequency in kHz, must use 5K or less for older National Insturments card
% end
% 
% if (NIDAQ_type==1)
%     s.addAnalogOutputChannel('dev1',0:1,'Voltage'); % for PCI-6036 which only has two analog outputs
% else
if Exp_Defaults.demoDAQ ~= 1; 
    s.addAnalogOutputChannel('dev1',0:3,'Voltage'); % other cards have 4 AOs
    
% end

  if (ExternalTrigger == 1)
    s.addTriggerConnection('External','dev1/PFI0','StartTrigger');
  end

end

% setup fields for Experiment structs
CCoutput1=[]; CCoutput2=[]; ExperimentName=''; LEDoutput=[]; LEDoutput2 = []; piezooutput=[]; SaveName='';
SetSweepNumber=1; cell1sweep=[]; cell2sweep=[]; 
pulsesorramps=0; % this sets the LEDoutput state, default to pulses
stims=[]; sweeps={}; testpulse=[]; thissweep=[]; timebase=[]; motorpulses=[]; 
motordir=[]; MP285struct=[]; deltaparam=[]; LED_state =[]; sweeps_DI={};
% create time vector for plotting across trials
trialtime=[]; DIOsweep = [];


Exp_Defaults = struct('Fs', Fs,'sweepduration', sweepduration,'ISI', ISI, ...
    'total_sweeps', total_sweeps, 'ExternalTrigger', ExternalTrigger, 'amplifier', amplifier, ...
    'VCexternalcommandsensitivity', VCexternalcommandsensitivity, 'CCexternalcommandsensitivity', ...
    CCexternalcommandsensitivity, 'ifsave', ifsave, 'demoDAQ', demoDAQ, ...
    'AO0', AO0, 'AO1', AO1, 'AO2', AO2, 'AO3', AO3, 'DIO_on', DIO_on, 'Lumencor_on', Lumencor_on);
ExpStruct = struct('CCoutput1', CCoutput1, 'CCoutput2', CCoutput2, 'ExperimentName', ExperimentName, 'LEDoutput', LEDoutput, 'LEDoutput2', LEDoutput, 'piezooutput', piezooutput, ...
    'SaveName', SaveName, 'SavePath', SavePath, 'SetSweepNumber', SetSweepNumber, 'cell1sweep', cell1sweep, 'cell2sweep', cell2sweep, ...
    'pulsesorramps', pulsesorramps, 'stims', stims, 'sweep_counter', sweep_counter, 'testpulse', testpulse, ...
    'thissweep', thissweep, 'timebase', timebase, 'motorpulses', motorpulses, 'motordir', motordir, 'MP285struct', MP285struct, ...
    'VisStimSeq', [], 'trialtime',trialtime, 'deltaparam', deltaparam, 'LED_state', LED_state,'DIOsweep', DIOsweep); 


% initialize analysis limits values
ExpStruct.analysis_limits.cell1= [0.5 0 0.68 0];
% ExpStruct.analysis_limits.cell1= [0.15 0 0.28 0]; % change to this for high frequency visual stimulation



% create isrunning field
ExpStruct.running = [];

% create TuningPlot_on field
ExpStruct.TuningPlot_on = 0;

% create MultiTuningPlot_on field
ExpStruct.MultiVisStimPlot_on = 0;

% create LED state fiedl
ExpStruct.LED_state = [];

% initalize Exp trial time
ExpStruct.trialtime = 0;

% set a defauft for number of steps in conditional experiment
ExpStruct.numSteps = 4;

% create random repeating stimulus sequence. Default lengths is 600 (changed from 300 4/13/2014). 
ExpStruct.stimulus_sequence=randrepvector(ExpStruct.numSteps^2,ExpStruct.numSteps^2,200);

% spiral scan defaults

ExpStruct.dampOsc.gain = 0.5; %max voltage to galvos
ExpStruct.dampOsc.damping1 = 1;
ExpStruct.dampOsc.phase = 1;
ExpStruct.dampOsc.DCoffset = 0; 
ExpStruct.dampOsc.duration = 5; % ms

% initialize current mod
ExpStruct.IVcurrentMod = 0;

% define threshold for identifying spikes from extacellular data (high pass
% filtered)
ExpStruct.unitThreshold = 0;



