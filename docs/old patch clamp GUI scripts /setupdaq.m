% clear workspace
clear all
% clearvars -EXCEPT MP285pointsList

% intialize globals
global Exp_Defaults ExpStruct globalTimer s LED Ramp cell1 cell2 h sweeps motor cellMappingGUI sweeps_DI

Exp_Defaults.demoDAQ = 0; % Set to 1 for demo DAQ when not connect to a real DAQ

%% create DAQ session
if Exp_Defaults.demoDAQ ~= 1

s = daq.createSession('ni');
s.addAnalogInputChannel('dev1',0:2,'Voltage');
s.Channels(1).InputType = 'SingleEnded';
s.Channels(2).InputType = 'SingleEnded';
s.Channels(3).InputType = 'SingleEnded';
%% add digital channels
% s.addDigitalChannel('dev1', 'Port0/Line0:7', 'OutputOnly');
s.addDigitalChannel('dev1', 'Port0/Line0:1', 'InputOnly');
s.addDigitalChannel('dev1', 'Port0/Line8:15', 'InputOnly');

end

%% create experiment structs
setup_structs


%% generate analog outputs
setup_input_output


%% setup experiment timer
globalTimer=timer('TimerFcn', 'acquire', 'TaskstoExecute', Exp_Defaults.total_sweeps, ...
    'Period',Exp_Defaults.ISI, 'ExecutionMode','fixedRate');%,'ErrorFcn', 'timer_error');

% globalTimer.BusyMode='error';

% store GUI handles in h for calling
s.Rate=Exp_Defaults.Fs;

h = guihandles(Acq);

%% set initial state of save checkbox
set(h.default_save_check, 'Value',Exp_Defaults.ifsave)

%% set the close request function
% this call back function executtes on asking to close the GUI and is setup
% to save certain data variables and structures in the workspace
set(Acq,'closerequestfcn',@close_req_fcn);

%% label the axes
labelaxes()

%% setup Zaber stage
% ZaberLinearStageSetup

%% get date in string format and automatically set experiment name
ExpStruct.ExperimentName = autoExptname();
set(h.ExperimentName, 'String', ExpStruct.ExperimentName);
ExpStruct.SaveName=strcat(ExpStruct.SavePath,ExpStruct.ExperimentName);

%% get Experiment parameters from previous experiment from same day if not first experiment
% 
load_old_Expt_params; 

