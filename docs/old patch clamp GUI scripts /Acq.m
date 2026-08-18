function varargout = Acq(varargin)

% ACQ MATLAB code for Acq.fig
%      ACQ, by itself, creates a new ACQ or raises the existing
%      singleton*.
%
%      H = ACQ returns the handle to a new ACQ or the handle to
%      the existing singleton*.
%
%      ACQ('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in ACQ.M with the given input arguments.
%
%      ACQ('Property','Value',...) creates a new ACQ or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before Acq_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to Acq_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help Acq

% Last Modified by G UIDE v2.5 13-Feb-2013 14:39:52

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @Acq_OpeningFcn, ...
                   'gui_OutputFcn',  @Acq_OutputFcn, ...
                   'gui_LayoutFcn',  [] , ...
                   'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT


% --- Executes just before Acq is made visible.
function Acq_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to Acq (see VARARGIN)

% Choose default command line output for Acq
handles.output = hObject;

% Update handles structure
guidata(hObject, handles);


% UIWAIT makes Acq wait for user response (see UIRESUME)
% uiwait(handles.figure1);


% --- Outputs from this function are returned to the command line.
function varargout = Acq_OutputFcn(hObject, eventdata, handles) 
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.output;



% --- Executes on button press in StopButton.
function StopButton_Callback(hObject, eventdata, handles)
global globalTimer Exp_Defaults s
stop(globalTimer)

function Whole_cell1_axes_CreateFcn(hObject, eventdata, handles)

% Hint: place code in OpeningFcn to populate Whole_cell1_axes

% --- Executes on button press in StartButton.
function StartButton_Callback(hObject, eventdata, handles)
global globalTimer h ExpStruct Exp_Defaults
if isempty(ExpStruct.SaveName)
    k = errordlg('Set experiment name')
end
% if using internal triggering
if (Exp_Defaults.ExternalTrigger==0)
    start(globalTimer)
% if using external triggering don't use timer fcn    
else
    
%     acquireNoInput()
    acquire()
end

function set_ISI_Callback(hObject, eventdata, handles)

% Hints: get(hObject,'String') returns contents of set_ISI as text
%        str2double(get(hObject,'String')) returns contents of set_ISI as a double
global Exp_Defaults globalTimer
Exp_Defaults.ISI=str2double(get(hObject,'String'));
if (Exp_Defaults.ExternalTrigger==0)
    stop(globalTimer); 
    globalTimer=timer('TimerFcn', 'acquire', 'TaskstoExecute', Exp_Defaults.total_sweeps, 'Period',Exp_Defaults.ISI, 'ExecutionMode','fixedRate');
end

% --- Executes during object creation, after setting all properties.
function set_ISI_CreateFcn(hObject, eventdata, handles)

global h Exp_Defaults
set(hObject,'String',num2str(Exp_Defaults.ISI));
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in ext_cmd_1_check.
function ext_cmd_1_check_Callback(hObject, eventdata, handles)
% Hint: get(hObject,'Value') returns toggle state of ext_cmd_1_check


function set_length_Callback(hObject, eventdata, handles)

global Exp_Defaults ExpStruct LED cell1 cell2 motor 
Exp_Defaults.sweepduration=str2double(get(hObject,'String'));

ExpStruct.timebase=linspace(0,Exp_Defaults.sweepduration,(Exp_Defaults.Fs*Exp_Defaults.sweepduration));
if ExpStruct.pulsesorramps==0
    ExpStruct.LEDoutput = makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
    ExpStruct.LEDoutput2 = makepulseoutputs(LED.pulse_starttime-10,LED.pulsenumber, LED.pulseduration+20, 5, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
elseif ExpStruct.pulsesorramps==1
    make_ramp_output
else
    ExpStruct.LEDoutput = makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
    ExpStruct.LEDoutput2 = makepulseoutputs(LED.pulse_starttime-10,LED.pulsenumber, LED.pulseduration+10, 5, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
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
ExpStruct.shutterTriggerOutput=makepulseoutputs(LED.pulse_starttime-10,LED.pulsenumber, LED.pulseduration+15, 1, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.digitalLEDoutput = makepulseoutputs(LED.pulse_starttime-5, LED.pulsenumber, LED.pulseduration+5, ExpStruct.digitalLED_on ,LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.sweepTrigger = makepulseoutputs(150, 1, 5, 1 ,1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);

pulse_starttime=300;
motorpulses = makepulseoutputs(pulse_starttime, motor.pulsenumber, motor.pulseduration, motor.pulseamp, motor.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
pulse_starttime=1000;
temp=motorpulses;
motorpulses = makepulseoutputs(pulse_starttime, motor.pulsenumber, motor.pulseduration, motor.pulseamp, motor.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.motorpulses=temp+motorpulses;
ExpStruct.motordir = makepulseoutputs(650, 1, 600, 5, 1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);  
ExpStruct.Lumencor_output = Digital_outputgen( LED.color , LED.pulse_starttime, LED.pulsenumber, LED.pulseduration, LED.pulsefrequency );

updateAOaxes



% --- Executes during object creation, after setting all properties.
function set_length_CreateFcn(hObject, eventdata, handles)

global Exp_Defaults
 set(hObject,'String',num2str(Exp_Defaults.sweepduration));
 
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
   
end



% --- Executes on button press in pushbutton5.
function pushbutton5_Callback(hObject, eventdata, handles)

makeoutputs


% --- Executes during object creation, after setting all properties.
function Whole_cell1_axes_Rs_CreateFcn(hObject, eventdata, handles)



% --- Executes during object creation, after setting all properties.
function ext_cmd_1_check_CreateFcn(hObject, eventdata, handles)

% --- Executes on button press in ext_cmd_2_check.
function ext_cmd_2_check_Callback(hObject, eventdata, handles)

% Hint: get(hObject,'Value') returns toggle state of ext_cmd_2_check

% --- Executes on button press in VC_toggle_WC1.
function VC_toggle_WC1_Callback(hObject, eventdata, handles)
% Hint: get(hObject,'Value') returns toggle state of VC_toggle_WC1


% --- Executes on button press in VC_toggle_WC2.
function VC_toggle_WC2_Callback(hObject, eventdata, handles)

% Hint: get(hObject,'Value') returns toggle state of VC_toggle_WC2



function pulseamp_Callback(hObject, eventdata, handles)
global LED
LED.pulseamp=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of pulseamp as text
%        str2double(get(hObject,'String')) returns contents of pulseamp as a double


% --- Executes during object creation, after setting all properties.
function pulseamp_CreateFcn(hObject, eventdata, handles)

global LED
set(hObject,'String',num2str(LED.pulseamp));

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function pulseduration_Callback(hObject, eventdata, handles)

global LED
LED.pulseduration=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of pulseduration as text
%        str2double(get(hObject,'String')) returns contents of pulseduration as a double


% --- Executes during object creation, after setting all properties.
function pulseduration_CreateFcn(hObject, eventdata, handles)

global LED
set(hObject,'String',num2str(LED.pulseduration));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function pulsenumber_Callback(hObject, eventdata, handles)

global LED
LED.pulsenumber=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of pulsenumber as text
%        str2double(get(hObject,'String')) returns contents of pulsenumber as a double


% --- Executes during object creation, after setting all properties.
function pulsenumber_CreateFcn(hObject, eventdata, handles)

global LED
set(hObject,'String',num2str(LED.pulsenumber));

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function pulsefrequency_Callback(hObject, eventdata, handles)

global LED
LED.pulsefrequency=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of pulsefrequency as text
%        str2double(get(hObject,'String')) returns contents of pulsefrequency as a double


% --- Executes during object creation, after setting all properties.
function pulsefrequency_CreateFcn(hObject, eventdata, handles)

global LED
set(hObject,'String',num2str(LED.pulsefrequency));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

   

function pulse_starttime_Callback(hObject, eventdata, handles)

global LED
LED.pulse_starttime=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of pulse_starttime as text
%        str2double(get(hObject,'String')) returns contents of pulse_starttime as a double


% --- Executes during object creation, after setting all properties.
function pulse_starttime_CreateFcn(hObject, eventdata, handles)

global LED
set(hObject,'String',num2str(LED.pulse_starttime));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function rampstart_voltage_Callback(hObject, eventdata, handles)

global LED Ramp
Ramp.rampstart_voltage=str2double(get(hObject,'String'));
LED.pulseamp2 = str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of rampstart_voltage as text
%        str2double(get(hObject,'String')) returns contents of rampstart_voltage as a double


% --- Executes during object creation, after setting all properties.
function rampstart_voltage_CreateFcn(hObject, eventdata, handles)

global Ramp
set(hObject,'String',num2str(Ramp.rampstart_voltage));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function rampend_voltage_Callback(hObject, eventdata, handles)

global Ramp
Ramp.rampend_voltage=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of rampend_voltage as text
%        str2double(get(hObject,'String')) returns contents of rampend_voltage as a double


% --- Executes during object creation, after setting all properties.
function rampend_voltage_CreateFcn(hObject, eventdata, handles)
% hObject    handle to rampend_voltage (see GCBO)

global Ramp
set(hObject,'String',num2str(Ramp.rampend_voltage));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function rampstart_time_Callback(hObject, eventdata, handles)

global Ramp
Ramp.rampstart_time=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of rampstart_time as text
%        str2double(get(hObject,'String')) returns contents of rampstart_time as a double


% --- Executes during object creation, after setting all properties.
function rampstart_time_CreateFcn(hObject, eventdata, handles)

global Ramp
set(hObject,'String',num2str(Ramp.rampstart_time));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function ramp_frequency_Callback(hObject, eventdata, handles)

global Ramp
Ramp.ramp_frequency=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of ramp_frequency as text
%        str2double(get(hObject,'String')) returns contents of ramp_frequency as a double


% --- Executes during object creation, after setting all properties.
function ramp_frequency_CreateFcn(hObject, eventdata, handles)

global Ramp
set(hObject,'String',num2str(Ramp.ramp_frequency));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on selection change in analsyis_popup.
function analsyis_popup_Callback(hObject, eventdata, handles)

val = get(hObject,'Value');
switch val
    case 1
        avg_traces
    case 2
        plot_amps
    case 3
        plot_charge
end 
% Hints: contents = cellstr(get(hObject,'String')) returns analsyis_popup contents as cell array
%        contents{get(hObject,'Value')} returns selected item from analsyis_popup


% --- Executes during object creation, after setting all properties.
function analsyis_popup_CreateFcn(hObject, ~, handles)

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in update_pulses_button.
function update_pulses_button_Callback(hObject, eventdata, handles)

global h ExpStruct Exp_Defaults LED Ramp
% LEDoutput timebase sweepduration pulsesorramps
ExpStruct.LEDoutput=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration)+LED.DCoffset1; %-.15 for keeping Monaco EOM at 0 mW output
ExpStruct.LEDoutput2=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp2, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration)+LED.DCoffset2;
% for Jenny's PV-ChR2 stim test
% ExpStruct.LEDoutput2=makepulseoutputs(LED.pulse_starttime+2000,4, 1000, Ramp.rampend_voltage/LED.pulseamp, 0.5, Exp_Defaults.Fs, Exp_Defaults.sweepduration)+1;

ExpStruct.shutterTriggerOutput=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration+15, 1, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.Lumencor_output(:,1)=ExpStruct.shutterTriggerOutput;
ExpStruct.digitalLEDoutput = makepulseoutputs(LED.pulse_starttime, LED.pulsenumber, LED.pulseduration+5, ExpStruct.digitalLED_on ,LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
% ExpStruct.LEDoutput=ExpStruct.LEDoutput.*ExpStruct.LEDoutput2;
ExpStruct.pulsesorramps=0;
[ ExpStruct.galvoxOutput, ExpStruct.galvoyOutput ] = updateGalvoVectors(LED.pulse_starttime, LED.pulsenumber, LED.pulseduration, Ramp.rampstart_voltage ,LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
updateAOaxes


% --- Executes on button press in VC_cell1_radio.
function VC_cell1_radio_Callback(hObject, eventdata, handles)

global h cell1 cell2 ExpStruct
if get(hObject,'Value')~=1
    ylabel(h.Whole_cell1_axes,'mV')
    % ylabel(h.CCoutput_axes,'pA')
    if get(h.LFP_check, 'Value')~=1 
        cell1.user_gain=20; % set gain to 20 for whole cell current clamp
    else
        cell1.user_gain=500; % set gain to 500 for LFP recording
    end
    
else
    cell1.user_gain=1;
    
    
    ylabel(h.Whole_cell1_axes,'pA')  
    % ylabel(h.CCoutput_axes,'mV')
end
ExpStruct.CCoutput1=makepulseoutputs(cell1.pulse_starttime,cell1.pulsenumber, cell1.pulseduration, cell1.pulseamp, cell1.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.CCoutput1=ExpStruct.CCoutput1/cell1.externalcommandsensitivity;
ExpStruct.CCoutput2=makepulseoutputs(cell2.pulse_starttime,cell2.pulsenumber, cell2.pulseduration, cell2.pulseamp, cell2.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.CCoutput2=ExpStruct.CCoutput2/cell1.externalcommandsensitivity;
% Hint: get(hObject,'Value') returns toggle state of VC_cell1_radio


% --- Executes on button press in VC_cell2_radio.
function VC_cell2_radio_Callback(hObject, eventdata, handles)

global h cell2
if get(hObject,'Value')~=1
    ylabel(h.Whole_cell2_axes,'mV')
    cell2.user_gain=20;
else
    ylabel(h.Whole_cell2_axes,'pA')  
    cell2.user_gain=1;
end
% Hint: get(hObject,'Value') returns toggle state of VC_cell2_radio


% --- Executes on button press in cmp_button.
function update_ramp_button_Callback(hObject, eventdata, handles)

global h Exp_Defaults ExpStruct Ramp
% global LEDoutput timebase sweepduration pulsesorramps
% ExpStruct.LEDoutput = make_ramp_output(Ramp.rampstart_time, Ramp.rampend_time, Ramp.rampstart_voltage, Ramp.rampend_voltage, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.LEDoutput =make_ramp_output(Ramp.rampstart_time, Ramp.ramp_duration,   Ramp.rampstart_voltage, Ramp.rampend_voltage, Exp_Defaults.Fs, Exp_Defaults.sweepduration)
ExpStruct.pulsesorramps=1;
updateAOaxes




% --- Executes on button press in updatePulse_ramp.
function updatePulse_ramp_Callback(hObject, eventdata, handles)

global h ExpStruct Exp_Defaults LED Ramp
% pulses=makecosineoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
pulses=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
%ExpStruct.LEDoutput = make_ramp_output(Ramp.rampstart_time, Ramp.ramp_duration, Ramp.rampstart_voltage, Ramp.rampend_voltage, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.LEDoutput =make_ramps(Ramp.rampstart_time, Ramp.ramp_duration, Ramp.ramp_frequency, Ramp.ramp_number, Ramp.rampstart_voltage, Ramp.rampend_voltage, Exp_Defaults.Fs, Exp_Defaults.sweepduration)
LEDoutput=ExpStruct.LEDoutput+pulses;
ExpStruct.pulsesorramps=2;
ExpStruct.LEDoutput=LEDoutput;
updateAOaxes

% --- Executes on button press in previoussweep_button.
function previoussweep_button_Callback(hObject, eventdata, handles)


global h ExpStruct Exp_Defaults sweeps

SetSweepNumber=ExpStruct.SetSweepNumber; 
thissweep=ExpStruct.thissweep;
sweep_counter=ExpStruct.sweep_counter;
sweepcount=size(sweeps);
if (SetSweepNumber >= sweepcount(2)) % if trying to view traces that don't exist yet get error
%     k = errordlg('No more sweeps');
else
    
val = get(h.Highpass_check, 'Value');
 
 
ExpStruct.SetSweepNumber=ExpStruct.SetSweepNumber-1;

value3 = get(h.record_cell2_check, 'Value'); % check if dual whole cell
 set(h.SetSweepNumber,'String',num2str(ExpStruct.SetSweepNumber));
sweeppoints=size(sweeps{ExpStruct.SetSweepNumber});
tim=linspace(0,sweeppoints(:,1)/Exp_Defaults.Fs,sweeppoints(:,1));
timStim=downsample(tim,10);

val4 = get(h.axes_hold_check, 'Value'); % check if dual whole cell
% if checked get current axes limits
if (val4 == 1)
    xlimits = get(h.sweep_display_axes,'xlim');
    ylimits = get(h.sweep_display_axes, 'ylim');
end

if (value3==1)
    thissweep=sweeps{ExpStruct.SetSweepNumber}; 
    thissweep1=thissweep(:,1);
%     thissweep1= smart_zero(thissweep1);
%     thissweep1 = zeroMultiStimTrace(thissweep1);
    thissweep2=thissweep(:,2);
%     thissweep2 = smart_zero(thissweep2);
    thisStim = ExpStruct.stims{SetSweepNumber+1};
    thisStim=thisStim(1);
    thisStim=thisStim{1};
     if (val == 1)
         thissweep1=highpass_filter(thissweep1); % if checked highpass filter
        end 
% compute and display velocity
    if get(h.Cell2_type_popup,'value')== 4 % if second channel is rotary encoder
%         [~, running_vector, times] = get_running_speed(thissweep2,0,Exp_Defaults.sweepduration);
% above line for use without Etach2 (just digital output)
        plot(h.sweep_display_axes,tim, thissweep1);
        plot(h.Whole_cell2_axes, tim, thissweep2);
        plot(h.LEDoutput_axes, timStim, thisStim);
    else
        plot(h.LEDoutput_axes, timStim, thisStim);
        plot(h.sweep_display_axes, ExpStruct.timebase, thissweep2,  tim, thissweep1);
    end
else
    thissweep=sweeps{ExpStruct.SetSweepNumber}; 
    thissweep=thissweep(:,1);
%     thissweep = smart_zero(thissweep);
%     thissweep=thissweep-mean(thissweep(1:20000));
        if (val == 1)
         thissweep=highpass_filter(thissweep); % if checked highpass filter
        end  
    plot(h.sweep_display_axes,tim, thissweep); % if just single cell just plot cell1
    plot(h.LEDoutput_axes, timStim, thisStim);
end

if val4 == 1 % if holding axes limits
    xlim(h.sweep_display_axes, [xlimits(1) xlimits(2)]);
    ylim(h.sweep_display_axes, [ylimits(1) ylimits(2)]);
end

xlabel(h.sweep_display_axes, 'seconds')

val5=get(h.Cell1_type_popup,'Value');
if val5==1
    ylabel(h.sweep_display_axes, 'pA')
else
    ylabel(h.sweep_display_axes, 'mV')
end


% set(h.stimulus_num,'String',num2str(ExpStruct.motorstim(ExpStruct.SetSweepNumber)));
if Exp_Defaults.DIO_on == 0 % if a barrel cortex experiment
    set(h.stimulus_num,'String',num2str(ExpStruct.stimulus_sequence(ExpStruct.SetSweepNumber)));
else
     set(h.stimulus_num,'String',num2str(ExpStruct.VisStimSeq(ExpStruct.SetSweepNumber)));
end
end


% --- Executes on button press in nextsweep_button.
function nextsweep_button_Callback(hObject, eventdata, handles)

global h ExpStruct Exp_Defaults sweeps

SetSweepNumber=ExpStruct.SetSweepNumber; 
thissweep=ExpStruct.thissweep;
sweep_counter=ExpStruct.sweep_counter;
sweepcount=size(sweeps);
if (SetSweepNumber >= sweepcount(2)) % if trying to view traces that don't exist yet get error
%     k = errordlg('No more sweeps');
else
    
val = get(h.Highpass_check, 'Value');
 
 
ExpStruct.SetSweepNumber=ExpStruct.SetSweepNumber+1;

value3 = get(h.record_cell2_check, 'Value'); % check if dual whole cell
 set(h.SetSweepNumber,'String',num2str(ExpStruct.SetSweepNumber));
sweeppoints=size(sweeps{ExpStruct.SetSweepNumber});
tim=linspace(0,sweeppoints(:,1)/Exp_Defaults.Fs,sweeppoints(:,1));
timStim=downsample(tim,10);

val4 = get(h.axes_hold_check, 'Value'); % check if dual whole cell
% if checked get current axes limits
if (val4 == 1)
    xlimits = get(h.sweep_display_axes,'xlim');
    ylimits = get(h.sweep_display_axes, 'ylim');
end

if (value3==1)
    thissweep=sweeps{ExpStruct.SetSweepNumber}; 
    thissweep1=thissweep(:,1);
%     thissweep1= smart_zero(thissweep1);
%     thissweep1 = zeroMultiStimTrace(thissweep1);
    thissweep2=thissweep(:,2);
%     thissweep2 = smart_zero(thissweep2);
    thisStim = ExpStruct.stims{SetSweepNumber+1};
    thisStim=thisStim(1);
    thisStim=thisStim{1};
     if (val == 1)
         thissweep1=highpass_filter(thissweep1); % if checked highpass filter
        end 
% compute and display velocity
    if get(h.Cell2_type_popup,'value')== 4 % if second channel is rotary encoder
%         [~, running_vector, times] = get_running_speed(thissweep2,0,Exp_Defaults.sweepduration);
% above line for use without Etach2 (just digital output)
        plot(h.sweep_display_axes,tim, thissweep1);
        plot(h.Whole_cell2_axes, tim, thissweep2);
        plot(h.LEDoutput_axes, timStim, thisStim);
    else
        plot(h.LEDoutput_axes, timStim, thisStim);
        plot(h.sweep_display_axes, ExpStruct.timebase, thissweep2,  tim, thissweep1);
    end
else
    thissweep=sweeps{ExpStruct.SetSweepNumber}; 
    thissweep=thissweep(:,1);
%     thissweep = smart_zero(thissweep);
%     thissweep=thissweep-mean(thissweep(1:20000));
        if (val == 1)
         thissweep=highpass_filter(thissweep); % if checked highpass filter
        end  
    plot(h.sweep_display_axes,tim, thissweep); % if just single cell just plot cell1
    plot(h.LEDoutput_axes, timStim, thisStim);
end

if val4 == 1 % if holding axes limits
    xlim(h.sweep_display_axes, [xlimits(1) xlimits(2)]);
    ylim(h.sweep_display_axes, [ylimits(1) ylimits(2)]);
end

xlabel(h.sweep_display_axes, 'seconds')

val5=get(h.Cell1_type_popup,'Value');
if val5==1
    ylabel(h.sweep_display_axes, 'pA')
else
    ylabel(h.sweep_display_axes, 'mV')
end


% set(h.stimulus_num,'String',num2str(ExpStruct.motorstim(ExpStruct.SetSweepNumber)));
if Exp_Defaults.DIO_on == 0 % if a barrel cortex experiment
    set(h.stimulus_num,'String',num2str(ExpStruct.stimulus_sequence(ExpStruct.SetSweepNumber)));
else
     set(h.stimulus_num,'String',num2str(ExpStruct.VisStimSeq(ExpStruct.SetSweepNumber)));
end
end


% --- Executes on button press in update_cc_cell1_button.
function update_cc_cell1_button_Callback(hObject, eventdata, handles)

global cell1 cell2 ExpStruct Exp_Defaults
ExpStruct.CCoutput1=makepulseoutputs(cell1.pulse_starttime,cell1.pulsenumber, cell1.pulseduration, cell1.pulseamp, cell1.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration, cell1.deltacurrentpulseamp);
ExpStruct.CCoutput1=ExpStruct.CCoutput1/cell1.externalcommandsensitivity; % scale by external command sensititvity under Current Clamp
updateAOaxes


% --- Executes on button press in update_cc_cell2_button.
function update_cc_cell2_button_Callback(hObject, eventdata, handles)

global cell2 cell1 ExpStruct Exp_Defaults
ExpStruct.CCoutput2=makepulseoutputs(cell2.pulse_starttime,cell2.pulsenumber, cell2.pulseduration, cell2.pulseamp, cell2.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.CCoutput2=ExpStruct.CCoutput2/Exp_Defaults.CCexternalcommandsensitivity;
updateAOaxes

function ccpulseamp2_Callback(hObject, eventdata, handles)

global cell2
cell2.pulseamp=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of ccpulseamp2 as text
%        str2double(get(hObject,'String')) returns contents of ccpulseamp2 as a double


% --- Executes during object creation, after setting all properties.
function ccpulseamp2_CreateFcn(hObject, eventdata, handles)

global cell2
set(hObject,'String',num2str(cell2.pulseamp));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function ccpulse_dur2_Callback(hObject, eventdata, handles)

global cell2
cell2.pulseduration=str2double(get(hObject,'String'));

% Hints: get(hObject,'String') returns contents of ccpulse_dur2 as text
%        str2double(get(hObject,'String')) returns contents of ccpulse_dur2 as a double


% --- Executes during object creation, after setting all properties.
function ccpulse_dur2_CreateFcn(hObject, eventdata, handles)

global cell2
set(hObject,'String',num2str(cell2.pulseduration));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function ccnumpulses2_Callback(hObject, eventdata, handles)

global cell2
cell2.pulsenumber=str2double(get(hObject,'String'));

% Hints: get(hObject,'String') returns contents of ccnumpulses2 as text
%        str2double(get(hObject,'String')) returns contents of ccnumpulses2 as a double


% --- Executes during object creation, after setting all properties.
function ccnumpulses2_CreateFcn(hObject, eventdata, handles)

global cell2
set(hObject,'String',num2str(cell2.pulsenumber));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function ccpulsestarttime2_Callback(hObject, eventdata, handles)

global cell2
cell2.pulse_starttime=str2double(get(hObject,'String'));

% Hints: get(hObject,'String') returns contents of ccpulsestarttime2 as text
%        str2double(get(hObject,'String')) returns contents of ccpulsestarttime2 as a double


% --- Executes during object creation, after setting all properties.
function ccpulsestarttime2_CreateFcn(hObject, eventdata, handles)

global cell2
set(hObject,'String',num2str(cell2.pulse_starttime));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function ccpulseamp1_Callback(hObject, eventdata, handles)

global cell1
cell1.pulseamp=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of ccpulseamp1 as text
%        str2double(get(hObject,'String')) returns contents of ccpulseamp1 as a double

% --- Executes during object creation, after setting all properties.
function ccpulseamp1_CreateFcn(hObject, eventdata, handles)

global cell1
set(hObject,'String',num2str(cell1.pulseamp));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function ccpulse_dur1_Callback(hObject, eventdata, handles)

global cell1
cell1.pulseduration=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of ccpulse_dur1 as text
%        str2double(get(hObject,'String')) returns contents of ccpulse_dur1 as a double


% --- Executes during object creation, after setting all properties.
function ccpulse_dur1_CreateFcn(hObject, eventdata, handles)

global cell1
set(hObject,'String',num2str(cell1.pulseduration));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function ccnumpulses1_Callback(hObject, eventdata, handles)

global cell1
cell1.pulsenumber=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of ccnumpulses1 as text
%        str2double(get(hObject,'String')) returns contents of ccnumpulses1 as a double


% --- Executes during object creation, after setting all properties.
function ccnumpulses1_CreateFcn(hObject, eventdata, handles)

global cell1
set(hObject,'String',num2str(cell1.pulsenumber));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function ccpulsestarttime1_Callback(hObject, eventdata, handles)

global cell1
cell1.pulse_starttime=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of ccpulsestarttime1 as text
%        str2double(get(hObject,'String')) returns contents of ccpulsestarttime1 as a double


% --- Executes during object creation, after setting all properties.
function ccpulsestarttime1_CreateFcn(hObject, eventdata, handles)

global cell1
set(hObject,'String',num2str(cell1.pulse_starttime));

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function SetSweepNumber_Callback(hObject, eventdata, handles)

global h ExpStruct Exp_Defaults sweeps
SetSweepNumber=ExpStruct.SetSweepNumber;
thissweep=ExpStruct.thissweep;

ExpStruct.SetSweepNumber=str2double(get(hObject,'String'));
sweeppoints=size(sweeps{ExpStruct.SetSweepNumber});
tim=linspace(0,sweeppoints(:,1)/Exp_Defaults.Fs,sweeppoints(:,1));
value3 = get(h.record_cell2_check, 'Value'); % check if dual whole cell

val4 = get(h.axes_hold_check, 'Value'); % check if dual whole cell
% if checked get current axes limits
if (val4 == 1)
    xlimits = get(h.sweep_display_axes,'xlim');
    ylimits = get(h.sweep_display_axes, 'ylim');
end

if (value3==1)
    thissweep=sweeps{ExpStruct.SetSweepNumber}; 
    thissweep1=thissweep(:,1);
    thissweep1= smart_zero(thissweep1);
    thissweep2=thissweep(:,2);
    thissweep2 = smart_zero(thissweep2);
    plot(h.sweep_display_axes,tim, thissweep1);
    plot(h.Whole_cell2_axes,tim, thissweep2);
else
    thissweep=sweeps{ExpStruct.SetSweepNumber}; 
    thissweep=thissweep(:,1);
    plot(h.sweep_display_axes,tim, thissweep); % if just single cell just plot cell1
end
set(h.stimulus_num,'String',num2str(ExpStruct.stimulus_sequence(ExpStruct.SetSweepNumber)));

if val4 == 1 % if holding axes limits
    xlim(h.sweep_display_axes, [xlimits(1) xlimits(2)]);
    ylim(h.sweep_display_axes, [ylimits(1) ylimits(2)]);
end

xlabel(h.sweep_display_axes, 'seconds')
val5=get(h.Cell1_type_popup,'Value');
if val5==1
    ylabel(h.sweep_display_axes, 'pA')
else
    ylabel(h.sweep_display_axes, 'mV')
end

% Hints: get(hObject,'String') returns contents of SetSweepNumber as text
%        str2double(get(hObject,'String')) returns contents of SetSweepNumber as a double


% --- Executes during object creation, after setting all properties.
function SetSweepNumber_CreateFcn(hObject, eventdata, handles)

global ExpStruct
SetSweepNumber=ExpStruct.SetSweepNumber;
SetSweepNumber=1;
set(hObject,'String',num2str(SetSweepNumber));

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function SavePath_Callback(hObject, eventdata, handles)

global ExpStruct
ExpStruct.SavePath=(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of SavePath as text
%        str2double(get(hObject,'String')) returns contents of SavePath as a double

% --- Executes during object creation, after setting all properties.
function SavePath_CreateFcn(hObject, eventdata, handles)

global ExpStruct
set(hObject,'String',ExpStruct.SavePath);

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function ExperimentName_Callback(hObject, eventdata, handles)

global ExpStruct

ExpStruct.ExperimentName=(get(hObject,'String'));
ExpStruct.SaveName=strcat(ExpStruct.SavePath,ExpStruct.ExperimentName);

function ExperimentName_CreateFcn(hObject, eventdata, handles)

global ExpStruct % ExperimentName
set(hObject,'String',ExpStruct.ExperimentName);

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function current_sweep_number_Callback(hObject, eventdata, handles)

% --- Executes during object creation, after setting all properties.
function current_sweep_number_CreateFcn(hObject, eventdata, handles)

global ExpStruct
set(hObject,'String',num2str(ExpStruct.sweep_counter));

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function ccpulsefreq2_Callback(hObject, eventdata, handles)

global cell2
cell2.pulsefrequency=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of ccpulsefreq2 as text
%        str2double(get(hObject,'String')) returns contents of ccpulsefreq2 as a double


% --- Executes during object creation, after setting all properties.
function ccpulsefreq2_CreateFcn(hObject, eventdata, handles)

global cell2
set(hObject,'String',num2str(cell2.pulsefrequency));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function ccpulsefreq1_Callback(hObject, eventdata, handles)

global cell1
cell1.pulsefrequency=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of ccpulsefreq1 as text
%        str2double(get(hObject,'String')) returns contents of ccpulsefreq1 as a double


% --- Executes during object creation, after setting all properties.
function ccpulsefreq1_CreateFcn(hObject, eventdata, handles)

global cell1
set(hObject,'String',num2str(cell1.pulsefrequency));

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in autogen_cell1_check.
function autogen_cell1_check_Callback(hObject, eventdata, handles)
% Hint: get(hObject,'Value') returns toggle state of autogen_cell1_check

global  Exp_Defaults h globalTimer ExpStruct motor LED 

val = get(h.autogen_cell1_check,'Value');

if val == 1 % after checking it
    Exp_Defaults.stored_sweepduration = Exp_Defaults.sweepduration;
    set_length(2); % set sweep length two seconds with current step going from 0.5-1.5 s

    % set ISI to 2.5s
    Exp_Defaults.stored_ISI = Exp_Defaults.ISI;
    Exp_Defaults.ISI=2.5;
    
    % turn off motor and LED/light
    ExpStruct.motorpulses = makepulseoutputs(1000, motor.pulsenumber, motor.pulseduration, 0, motor.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
    ExpStruct.LEDoutput = makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, 0, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
else
    
    set_length(Exp_Defaults.stored_sweepduration); % set sweep length two seconds with current step going from 0.5-1.5 s

    % set ISI to 2. 5s
    Exp_Defaults.ISI=Exp_Defaults.stored_ISI;
end

if (Exp_Defaults.ExternalTrigger==0)
    stop(globalTimer); 
    globalTimer=timer('TimerFcn', 'acquire', 'TaskstoExecute', Exp_Defaults.total_sweeps, 'Period',Exp_Defaults.ISI, 'ExecutionMode','fixedRate');
end


% --- Executes on button press in autogen_cell2_check.
function autogen_cell2_check_Callback(hObject, eventdata, handles)

% Hint: get(hObject,'Value') returns toggle state of autogen_cell2_check

function deltacurrentpulseamp_Callback(hObject, eventdata, handles)

global cell1
cell1.deltacurrentpulseamp=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of deltacurrentpulseamp2 as text
%        str2double(get(hObject,'String')) returns contents of deltacurrentpulseamp2 as a double

% --- Executes during object creation, after setting all properties.
function deltacurrentpulseamp_CreateFcn(hObject, eventdata, handles)

global cell1
set(hObject,'String',num2str(cell1.deltacurrentpulseamp));

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function deltacurrentpulseamp2_Callback(hObject, eventdata, handles)

global cell2
cell2.deltacurrentpulseamp2=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of deltacurrentpulseamp2 as text
%        str2double(get(hObject,'String')) returns contents of deltacurrentpulseamp2 as a double


% --- Executes during object creation, after setting all properties.
function deltacurrentpulseamp2_CreateFcn(hObject, eventdata, handles)

global cell2
set(hObject,'String',cell2.deltacurrentpulseamp);

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in hold_sweep_display_axes.
function hold_sweep_display_axes_Callback(hObject, eventdata, handles)

global h
hold(h.sweep_display_axes);
% Hint: get(hObject,'Value') returns toggle state of hold_sweep_display_axes


% --- Executes on button press in record_cell2_check.
function record_cell2_check_Callback(hObject, eventdata, handles)
% Hint: get(hObject,'Value') returns toggle state of record_cell2_check

% --- Executes on button press in Highpass_check.
function Highpass_check_Callback(hObject, eventdata, handles)
global h

% Hint: get(hObject,'Value') returns toggle state of Highpass_check


function highpass_freq1_Callback(hObject, eventdata, handles)
% Hints: get(hObject,'String') returns contents of highpass_freq1 as text
%        str2double(get(hObject,'String')) returns contents of highpass_freq1 as a double

% --- Executes during object creation, after setting all properties.
function highpass_freq1_CreateFcn(hObject, eventdata, handles)

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes during object creation, after setting all properties.
function Whole_cell2_axes_CreateFcn(hObject, eventdata, handles)

% Hint: place code in OpeningFcn to populate Whole_cell2_axes

% --- Executes on button press in ExtTrigger_Button.
function ExtTrigger_Button_Callback(hObject, eventdata, handles)

global Exp_Defaults s
% Hint: get(hObject,'Value') returns toggle state of ExtTrigger_toggle
Trig_value = get(hObject, 'Value');
if (Trig_value == 1)
    Exp_Defaults.ExternalTrigger = 1;
        if (isempty(s.Connections)) % check if external trigger connection doesn't exists
            s.addTriggerConnection('External','dev1/PFI0','StartTrigger');
        end
else
    Exp_Defaults.ExternalTrigger = 0;
    s.removeConnection(1);
end


% --- Executes on selection change in Cell1_type_popup.
function Cell1_type_popup_Callback(hObject, eventdata, handles)

global h cell1 ExpStruct LED Exp_Defaults
val = get(hObject,'Value');
switch val
    case 1
        cell1.user_gain=1;
        ylabel(h.Whole_cell1_axes,'pA')
        cell1.externalcommandsensitivity=20;
        set(h.Cell1_Cmd_popup, 'String', 'Voltage Clamp');
        cell1.pulseamp = 4;
        set(h.ccpulseamp1, 'String', num2str(cell1.pulseamp))
        update_cc_cell1_button_Callback;
        ylabel(h.CCoutput_axes, 'mV');
        % set color from UV to green for QAQ experiments 
%         LED.color=4;
%         set(h.Lumencor_color,'String',num2str(LED.color));
%         ExpStruct.Lumencor_output = Digital_outputgen( LED.color , LED.pulse_starttime, LED.pulseduration );
    case 2
        cell1.user_gain=20;
        ylabel(h.Whole_cell1_axes,'mV')
        if strcmp(Exp_Defaults.amplifier, 'axopatch200B')
            cell1.externalcommandsensitivity=2000;
        else
            cell1.externalcommandsensitivity=400;
        end
        
        set(h.Cell1_Cmd_popup, 'String', 'Current Clamp');
        cell1.pulseamp = 0;
        set(h.ccpulseamp1, 'String', num2str(cell1.pulseamp))
        update_cc_cell1_button_Callback;
        ylabel(h.CCoutput_axes, 'pA');
    case 3
        cell1.user_gain=500;
        ylabel(h.Whole_cell1_axes,'mV')
end 
% Hints: contents = cellstr(get(hObject,'String')) returns Cell1_type_popup contents as cell array
%        contents{get(hObject,'Value')} returns selected item from Cell1_type_popup


% --- Executes during object creation, after setting all properties.
function Cell1_type_popup_CreateFcn(hObject, eventdata, handles)

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on selection change in Cell2_type_popup.
function Cell2_type_popup_Callback(hObject, eventdata, handles)

global h cell2
val = get(hObject,'Value');
switch val
    case 1
        cell2.user_gain=1;
        ylabel(h.Whole_cell2_axes,'pA')
        cell2.externalcommandsensitivity=20;
    case 2
        cell2.user_gain=20;
        ylabel(h.Whole_cell2_axes,'mV')
        cell2.externalcommandsensitivity=400;
    case 3
        cell2.user_gain=500;
        ylabel(h.Whole_cell2_axes,'mV')
    case 4
        cell2.user_gain=1; % should be 1 but set to 1/1000 to correct for multiplication in acquire function
        ylabel(h.Whole_cell2_axes, 'Volts')
end 
% Hints: contents = cellstr(get(hObject,'String')) returns Cell2_type_popup contents as cell array
%        contents{get(hObject,'Value')} returns selected item from Cell2_type_popup


% --- Executes during object creation, after setting all properties.
function Cell2_type_popup_CreateFcn(hObject, eventdata, handles)

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in AcquireBarrels_button.
function AcquireBarrels_button_Callback(hObject, eventdata, handles)

MappingSetup
% Hint: get(hObject,'Value') returns toggle state of AcquireBarrels_button


% --- Executes on selection change in online_analysis_popup.
function online_analysis_popup_Callback(hObject, eventdata, handles)
% Hints: contents = cellstr(get(hObject,'String')) returns online_analysis_popup contents as cell array
%        contents{get(hObject,'Value')} returns selected item from online_analysis_popup
contents = cellstr(get(hObject,'String'));
val = contents{get(hObject,'Value')};


% --- Executes during object creation, after setting all properties.
function online_analysis_popup_CreateFcn(hObject, eventdata, handles)

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in cursrosbutton.
function cursrosbutton_Callback(hObject, eventdata, handles)
% hObject    handle to cursrosbutton (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)




% --- Executes on button press in addcursors_radio.
function addcursors_radio_Callback(hObject, eventdata, handles)
% hObject    handle to addcursors_radio (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global h ExpStruct
% Hint: get(hObject,'Value') returns toggle state of addcursors_radio
if get(hObject, 'Value') == 1
    if isfield(ExpStruct,'analysis_limits')
        dualcursor([ExpStruct.analysis_limits.cell1(1) ExpStruct.analysis_limits.cell1(3)],[],[],[],h.Whole_cell1_axes); 
    else ExpStruct.analysis_limits.cell1
        dualcursor('on',[],[],[],h.Whole_cell1_axes); 
    end
 else 
    dualcursor('off',[],[],[],h.Whole_cell1_axes); 
end    
 


% --- Executes on button press in addcursors_radio2.
function addcursors_radio2_Callback(hObject, eventdata, handles)

global h ExpStruct
% Hint: get(hObject,'Value') returns toggle state of addcursors_radio
if get(hObject, 'Value') == 1
    if isfield(ExpStruct,'analysis_limits')
        dualcursor([ExpStruct.analysis_limits.cell2(1) ExpStruct.analysis_limits.cell2(3)],[],[],[],h.Whole_cell2_axes); 
    else
        dualcursor('on',[],[],[],h.Whole_cell2_axes); 
    end
 else 
    dualcursor('off',[],[],[],h.Whole_cell2_axes); 
end    


% --- Executes on button press in get_limits_button.
function get_limits_button_Callback(hObject, eventdata, handles)
global ExpStruct h
if (get(h.addcursors_radio,'Value')==1)
ExpStruct.analysis_limits.cell1 = dualcursor(h.Whole_cell1_axes);
end
if (get(h.addcursors_radio2,'Value')==1)
ExpStruct.analysis_limits.cell2 = dualcursor(h.Whole_cell2_axes);
end


% --- Executes on button press in loadexp_button.
function loadexp_button_Callback(hObject, eventdata, handles)

% clear all
global ExpStruct h

loadname=ExpStruct.SaveName;


load(loadname, 'sweeps', 'Exp_Defaults', 'ExpStruct', 'LED', 'Ramp', 'cell1', 'cell2'); %, 'motor'); 
% plot
plot(h.Whole_cell1_axes,ExpStruct.timebase,ExpStruct.cell1sweep);
plot(h.Whole_cell1_axes_Ih,cell1.holding_i,'o');
plot(h.Whole_cell1_axes_Rs,cell1.series_r,'o');
plot(h.Whole_cell1_axes_Ir,cell1.input_r,'o');
plot(h.LEDoutput_axes,ExpStruct.timebase, ExpStruct.LEDoutput);
plot(h.CCoutput_axes,ExpStruct.timebase, ExpStruct.CCoutput1, ExpStruct.timebase, ExpStruct.CCoutput2);

value3 = get(h.record_cell2_check, 'Value');
if (value3 == 1) % if recording two cells
    plot(h.Whole_cell2_axes,ExpStruct.timebase,ExpStruct.cell2sweep);
    plot(h.Whole_cell2_axes_Ih,cell2.holding_i,'o');
    plot(h.Whole_cell2_axes_Rs,cell2.series_r,'o');
    plot(h.Whole_cell2_axes_Ir,cell2.input_r,'o');
end
set(h.current_sweep_number,'String',num2str(ExpStruct.sweep_counter));
ExpStruct.SetSweepNumber = 1;
set(h.SetSweepNumber,'String',num2str(1));
plot(h.sweep_display_axes, ExpStruct.timebase, sweeps{1}); 
updateAOaxes;   

% update Expt_Params in GUI
try
    set(h.genotype,'String',(ExpStruct.Expt_Params.genotype));
    set(h.age,'String',(ExpStruct.Expt_Params.age));
    set(h.virus,'String',(ExpStruct.Expt_Params.virus));
    set(h.lightsource,'String',(ExpStruct.Expt_Params.lightsource));
    set(h.internal,'String',(ExpStruct.Expt_Params.internal));
    set(h.brainregion,'String',(ExpStruct.Expt_Params.brainregion));
    set(h.animal_number,'String',(ExpStruct.Expt_Params.animal_number));
catch
    set(h.genotype,'String',('n/a'));
    set(h.age,'String',('n/a'));
    set(h.virus,'String',('n/a'));
    set(h.lightsource,'String',('n/a'));
    set(h.internal,'String',('n/a'));
    set(h.brainregion,'String',('n/a'));
    set(h.animal_number,'String',('n/a'));
end

% update other params
val=get(h.Cell2_type_popup,'value');
% set(h.Cell2_type_popup,val);


% --- Executes on button press in TuningPlot_Setup.
function TuningPlot_Setup_Callback(hObject, eventdata, handles)
% hObject    handle to TuningPlot_Setup (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
TuningFcnSetup
ExpStruct.TuningPlot_on = 1;
% Hint: get(hObject,'Value') returns toggle state of TuningPlot_Setup


% --- Executes on button press in SaveExpt_button.
function SaveExpt_button_Callback(hObject, eventdata, handles)
global ExpStruct  cell1 cell2 LED Ramp ExpStruct Exp_Defaults h s sweeps sweeps_DI
button=questdlg('Are you sure?');

if strcmp(button, 'Yes')
    save(ExpStruct.SaveName);
end


% --- Executes on button press in mstim_check.
function mstim_check_Callback(hObject, eventdata, handles)
% hObject    handle to mstim_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
ZaberLinearStageSetup
% Hint: get(hObject,'Value') returns toggle state of mstim_check



function set_fixed_pulses_Callback(hObject, eventdata, handles)
% hObject    handle to set_fixed_pulses (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global motor ExpStruct Exp_Defaults
motor.fixed_pulses=str2double(get(hObject,'String'));
motor.pulsenumber=motor.fixed_pulses;
motorpulsefrequency=7500;
motorpulseamplitude=5;
motorpulseduration=0.03;
motorpulsestarttime=1000;
motorpulses = makemotorpulses(motorpulsestarttime, motor.pulsenumber, motorpulseduration, motorpulseamplitude, motorpulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
motorpulsestarttime=2500;
temp=motorpulses;
motorpulses = makemotorpulses(motorpulsestarttime, motor.pulsenumber, motorpulseduration, motorpulseamplitude, motorpulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
ExpStruct.motorpulses=temp+motorpulses;

% Hints: get(hObject,'String') returns contents of set_fixed_pulses as text
%        str2double(get(hObject,'String')) returns contents of set_fixed_pulses as a double


% --- Executes during object creation, after setting all properties.
function set_fixed_pulses_CreateFcn(hObject, eventdata, handles)
% hObject    handle to set_fixed_pulses (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called
global motor
set(hObject,'String',num2str(motor.fixed_pulses));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in default_save_check.
function default_save_check_Callback(hObject, eventdata, handles)
% hObject    handle to default_save_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of default_save_check


% --- Executes on button press in new_exp_button.
function new_exp_button_Callback(hObject, eventdata, handles)
% hObject    handle to new_exp_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct  cell1 cell2 LED Ramp ExpStruct Exp_Defaults h sweeps s 
    
   if isfield(ExpStruct, 'TuningPlot_on')
    if ExpStruct.TuningPlot_on == 1
        close(TuningPlot)
    end
    
    if ExpStruct.MultiVisStimPlot_on ==1
       close(MultiVisStimPlot)
    end
   end
   
   try
       close(ExpStruct.doseResponseStruct.doseResponsePlot)
   end
   
   try
       close(ExpStruct.MP285struct.PSFplot)
   end
   
   try
       close(ExpStruct.MP285struct.cellMappingPlot)
   end
   
   try
       close(CellMapping)
   end
   
%     ExpStruct.testpulse = makepulseoutputs(50,1, 50, -0.2, 1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
%     [AO0 AO1 AO2 AO3] = analogoutput_gen();
%     AO3 = zeros(length(ExpStruct.timebase),1);
%     s.queueOutputData([ExpStruct.sweepTrigger ExpStruct.Lumencor_output ExpStruct.digitalLEDoutput AO0 AO1 AO2 AO3 ]);
%     data = s.startForeground();
close(Acq)


% --- Executes on selection change in update_param_popup.
function update_param_popup_Callback(hObject, eventdata, handles)
% hObject    handle to update_param_popup (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = cellstr(get(hObject,'String')) returns update_param_popup contents as cell array
%        contents{get(hObject,'Value')} returns selected item from update_param_popup


% --- Executes during object creation, after setting all properties.
function update_param_popup_CreateFcn(hObject, eventdata, handles)
% hObject    handle to update_param_popup (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



	
% hObject    handle to deltaparam (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
ExpStruct.deltaparam=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of deltaparam as text
%        str2double(get(hObject,'String')) returns contents of deltaparam as a double


% --- Executes during object creation, after setting all properties.
function deltaparam_CreateFcn(hObject, eventdata, handles)
% hObject    handle to deltaparam (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called
global ExpStruct
set(hObject,'String',num2str(ExpStruct.deltaparam));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in auto_update_param_check.
function auto_update_param_check_Callback(hObject, eventdata, handles)
% first create stimulus order vector
global ExpStruct Exp_Defaults
numStimTypes = 10;
ExpStruct.stimOrder = randrepvector(numStimTypes , numStimTypes, 100 );
ExpStruct.testPulseFrequencies = [0, 8, 16, 24, 32, 40, 48, 56, 64, 72];
% Hint: get(hObject,'Value') returns toggle state of auto_update_param_check



function stimulus_num_Callback(hObject, eventdata, handles)
% hObject    handle to stimulus_num (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of stimulus_num as text
%        str2double(get(hObject,'String')) returns contents of stimulus_num as a double


% --- Executes during object creation, after setting all properties.
function stimulus_num_CreateFcn(hObject, eventdata, handles)
% hObject    handle to stimulus_num (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in pause_button.
function pause_button_Callback(hObject, eventdata, handles)
% hObject    handle to pause_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global Exp_Defaults h
Trig_value = get(hObject, 'Value');
ExtTrig_value = get(h.ExtTrigger_Button, 'Value');
if (Trig_value == 1)
    Exp_Defaults.ExternalTrigger = 0;
else
    if ExtTrig_value == 1
        Exp_Defaults.ExternalTrigger = 1;
%         acquireNoInput()
    end
end


% --- Executes on button press in seal_test_open_button.
function seal_test_open_button_Callback(hObject, eventdata, handles)
% hObject    handle to seal_test_open_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
setup_seal
% Hint: get(hObject,'Value') returns toggle state of seal_test_open_button


% --- Executes on button press in Alt_LED_state.
function Alt_LED_state_Callback(hObject, eventdata, handles)
% hObject    handle to Alt_LED_state (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct LED Exp_Defaults

% this ensures the first trial the LED is off
if ExpStruct.sweep_counter == 1
     ExpStruct.LEDoutput = makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, 0, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration)
end
updateAOaxes

% Hint: get(hObject,'Value') returns toggle state of Alt_LED_state


% --- Executes on button press in DIO_on_check.
function DIO_on_check_Callback(hObject, eventdata, handles)
% hObject    handle to DIO_on_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global Exp_Defaults h
val = get(h.DIO_on_check, 'Value');
if val == 1
    Exp_Defaults.DIO_on = 1; 
else 
    Exp_Defaults.DIO_on = 0; 
end
 
% Hint: get(hObject,'Value') returns toggle state of DIO_on_check


% --- Executes on button press in update_Lumencor.
function update_Lumencor_Callback(hObject, eventdata, handles)
% hObject    handle to update_Lumencor (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct LED Exp_Defaults h
val=get(h.Lumencor_check, 'Value'); 
if val == 1
   ExpStruct.Lumencor_output = Digital_outputgen( LED.color , LED.pulse_starttime, LED.pulsenumber, LED.pulseduration, LED.pulsefrequency );
   ExpStruct.LEDoutput=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, 0, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
else
   ExpStruct.Lumencor_output = ones(Exp_Defaults.Fs*Exp_Defaults.sweepduration,6);
   ExpStruct.LEDoutput=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
end

updateAOaxes


function ramp_endtime_Callback(hObject, eventdata, handles)
% hObject    handle to rampend_time (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global Ramp 
Ramp.rampend_time=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of rampend_time as text
%        str2double(get(hObject,'String')) returns contents of rampend_time as a double


% --- Executes during object creation, after setting all properties.
function rampend_time_CreateFcn(hObject, eventdata, handles)
% hObject    handle to rampend_time (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function ramp_number_Callback(hObject, eventdata, handles)
% hObject    handle to ramp_number (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global Ramp 
Ramp.ramp_number=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of ramp_number as text
%        str2double(get(hObject,'String')) returns contents of ramp_number as a double


% --- Executes during object creation, after setting all properties.
function ramp_number_CreateFcn(hObject, eventdata, handles)
% hObject    handle to ramp_number (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called
global Ramp
set(hObject,'String',num2str(Ramp.ramp_number));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes during object creation, after setting all properties.
function ramp_endtime_CreateFcn(hObject, eventdata, handles)
% hObject    handle to ramp_endtime (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called
global Ramp 
Ramp.rampend_time=str2double(get(hObject,'String'));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function ramp_duration_Callback(hObject, eventdata, handles)
% hObject    handle to ramp_duration (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global Ramp 
Ramp.ramp_duration=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of ramp_duration as text
%        str2double(get(hObject,'String')) returns contents of ramp_duration as a double


% --- Executes during object creation, after setting all properties.
function ramp_duration_CreateFcn(hObject, eventdata, handles)
% hObject    handle to ramp_duration (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called
global Ramp
set(hObject,'String',num2str(Ramp.ramp_duration));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in axes_hold_check.
function axes_hold_check_Callback(hObject, eventdata, handles)
% hObject    handle to axes_hold_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of axes_hold_check


% --- Executes on button press in Lumencor_check.
function Lumencor_check_Callback(hObject, eventdata, handles)
% hObject    handle to Lumencor_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct LED Exp_Defaults h
val=get(h.Lumencor_check, 'Value'); 
if val == 1
   ExpStruct.Lumencor_output = Digital_outputgen( LED.color , LED.pulse_starttime, LED.pulsenumber, LED.pulseduration, LED.pulsefrequency );
   ExpStruct.LEDoutput=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, 0, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
else
   ExpStruct.Lumencor_output = ones(Exp_Defaults.Fs*Exp_Defaults.sweepduration,6);
   ExpStruct.LEDoutput=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
end

updateAOaxes
% Hint: get(hObject,'Value') returns toggle state of Lumencor_check


% --- Executes on button press in spectrum_check.
function spectrum_check_Callback(hObject, eventdata, handles)
% hObject    handle to spectrum_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct LED h

% Hint: get(hObject,'Value') returns toggle state of spectrum_check
val=get(h.spectrum_check, 'Value'); 
if val == 1
    ExpStruct.Lumencor_output= spectrum_stim();
else
   ExpStruct.Lumencor_output = Digital_outputgen( LED.color , LED.pulse_starttime, LED.pulsenumber, LED.pulseduration, LED.pulsefrequency );
end
updateAOaxes


function Lumencor_color_Callback(hObject, eventdata, handles)
% hObject    handle to Lumencor_color (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global LED ExpStruct
LED.color=str2double(get(hObject,'String'));
ExpStruct.Lumencor_output = Digital_outputgen( LED.color , LED.pulse_starttime, LED.pulsenumber, LED.pulseduration, LED.pulsefrequency );
% Hints: get(hObject,'String') returns contents of Lumencor_color as text
%        str2double(get(hObject,'String')) returns contents of Lumencor_color as a double


% --- Executes during object creation, after setting all properties.
function Lumencor_color_CreateFcn(hObject, eventdata, handles)
% hObject    handle to Lumencor_color (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called
global LED ExpStruct
set(hObject,'String',num2str(LED.color));

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in MultiLED_check.
function MultiLED_check_Callback(hObject, eventdata, handles)
% hObject    handle to MultiLED_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct Exp_Defaults

% Hint: get(hObject,'Value') returns toggle state of MultiLED_check



function genotype_Callback(hObject, eventdata, handles)
% hObject    handle to genotype (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
    global ExpStruct
    ExpStruct.Expt_Params.genotype=(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of genotype as text
%        str2double(get(hObject,'String')) returns contents of genotype as a double


% --- Executes during object creation, after setting all properties.
function genotype_CreateFcn(hObject, eventdata, handles)
% hObject    handle to genotype (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called
% global ExpStruct
% set(hObject,'String',num2str(ExpStruct.Expt_Params.genotype));
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function age_Callback(hObject, eventdata, handles)
% hObject    handle to age (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structureglobal ExpStruct
global ExpStruct
ExpStruct.Expt_Params.age=(get(hObject,'String'));

% Hints: get(hObject,'String') returns contents of age as text
%        str2double(get(hObject,'String')) returns contents of age as a double


% --- Executes during object creation, after setting all properties.
function age_CreateFcn(hObject, eventdata, handles)
% hObject    handle to age (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function virus_Callback(hObject, eventdata, handles)
% hObject    handle to virus (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
ExpStruct.Expt_Params.virus=(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of virus as text
%        str2double(get(hObject,'String')) returns contents of virus as a double


% --- Executes during object creation, after setting all properties.
function virus_CreateFcn(hObject, eventdata, handles)
% hObject    handle to virus (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in checkbox22.
function checkbox22_Callback(hObject, eventdata, handles)
% hObject    handle to checkbox22 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of checkbox22



function lightsource_Callback(hObject, eventdata, handles)
% hObject    handle to lightsource (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
ExpStruct.Expt_Params.lightsource=(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of lightsource as text
%        str2double(get(hObject,'String')) returns contents of lightsource as a double


% --- Executes during object creation, after setting all properties.
function lightsource_CreateFcn(hObject, eventdata, handles)
% hObject    handle to lightsource (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


function internal_Callback(hObject, eventdata, handles)
% hObject    handle to internal (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
ExpStruct.Expt_Params.internal=(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of internal as text
%        str2double(get(hObject,'String')) returns contents of internal as a double


% --- Executes during object creation, after setting all properties.
function internal_CreateFcn(hObject, eventdata, handles)
% hObject    handle to internal (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function brainregion_Callback(hObject, eventdata, handles)
% hObject    handle to brainregion (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
ExpStruct.Expt_Params.brainregion=(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of brainregion as text
%        str2double(get(hObject,'String')) returns contents of brainregion as a double


% --- Executes during object creation, after setting all properties.
function brainregion_CreateFcn(hObject, eventdata, handles)
% hObject    handle to brainregion (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function animal_number_Callback(hObject, eventdata, handles)
% hObject    handle to animal_number (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of animal_number as text
%        str2double(get(hObject,'String')) returns contents of animal_number as a double
global ExpStruct
ExpStruct.Expt_Params.animal_number=(get(hObject,'String'));

% --- Executes during object creation, after setting all properties.
function animal_number_CreateFcn(hObject, eventdata, handles)
% hObject    handle to animal_number (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in wholecell1_axes_hold_check.
function wholecell1_axes_hold_check_Callback(hObject, eventdata, handles)
% hObject    handle to wholecell1_axes_hold_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of wholecell1_axes_hold_check



function experiment_time_Callback(hObject, eventdata, handles)
% hObject    handle to experiment_time (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of experiment_time as text
%        str2double(get(hObject,'String')) returns contents of experiment_time as a double


% --- Executes during object creation, after setting all properties.
function experiment_time_CreateFcn(hObject, eventdata, handles)
% hObject    handle to experiment_time (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function cell_depth_Callback(hObject, eventdata, handles)
% hObject    handle to cell_depth (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
ExpStruct.Expt_Params.cell_depth=(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of cell_depth as text
%        str2double(get(hObject,'String')) returns contents of cell_depth as a double


% --- Executes during object creation, after setting all properties.
function cell_depth_CreateFcn(hObject, eventdata, handles)
% hObject    handle to cell_depth (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in OpenMultiStimPlot.
function OpenMultiStimPlot_Callback(hObject, eventdata, handles)
% hObject    handle to OpenMultiStimPlot (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
MultiVisStimSetup;
ExpStruct.MultiVisStimPlot_on = 1;


% --- Executes on button press in FIcurveStim.
function FIcurveStim_Callback(hObject, eventdata, handles)
% hObject    handle to FIcurveStim (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct cell1 Exp_Defaults

ExpStruct.CCoutput1=makepulseoutputs(cell1.pulse_starttime,cell1.pulsenumber, cell1.pulseduration, ...
    -50, cell1.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration, cell1.deltacurrentpulseamp);
ExpStruct.CCoutput1=ExpStruct.CCoutput1/Exp_Defaults.CCexternalcommandsensitivity;
updateAOaxes


% --- Executes on button press in IVcurve_check.
function IVcurve_check_Callback(hObject, eventdata, handles)
% hObject    handle to IVcurve_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
ExpStruct.IVcurveStartSweep = ExpStruct.sweep_counter;
ExpStruct.IVparams.trialsPerVoltage = 44;
ExpStruct.IVparams.numVoltages = 8;
ExpStruct.IVparams.voltageStepSize = 8;


% --- Executes on selection change in Cell1_Cmd_popup.
function Cell1_Cmd_popup_Callback(hObject, eventdata, handles)
% hObject    handle to Cell1_Cmd_popup (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = cellstr(get(hObject,'String')) returns Cell1_Cmd_popup contents as cell array
%        contents{get(hObject,'Value')} returns selected item from Cell1_Cmd_popup


% --- Executes during object creation, after setting all properties.
function Cell1_Cmd_popup_CreateFcn(hObject, eventdata, handles)
% hObject    handle to Cell1_Cmd_popup (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in alt_QAQ_Light.
function alt_QAQ_Light_Callback(hObject, eventdata, handles)
% hObject    handle to alt_QAQ_Light (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
global h
val_LumencorDoseResponse = get(h.LumencorDoseResponseCheck, 'Value');
if val_LumencorDoseResponse == 1
    set_lumencor_intensity(100, 1);
    set_lumencor_intensity(100, 4);
end
% Hint: get(hObject,'Value') returns toggle state of alt_QAQ_Light


% --- Executes on button press in LumencorDoseResponseCheck.
function LumencorDoseResponseCheck_Callback(hObject, eventdata, handles)
% hObject    handle to LumencorDoseResponseCheck (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
ExpStruct.LumencorIntensity = zeros(ExpStruct.sweep_counter,1);
openLumencor;
% Hint: get(hObject,'Value') returns toggle state of LumencorDoseResponseCheck


% --- Executes on button press in LEDoutput2_check.
function LEDoutput2_check_Callback(hObject, eventdata, handles)
% hObject    handle to LEDoutput2_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of LEDoutput2_check
global ExpStruct h LED Exp_Defaults
val=get(h.LEDoutput2_check, 'Value'); 
if val == 1
   ExpStruct.LEDoutput=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, 0, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
   ExpStruct.LEDoutput2=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
else
   ExpStruct.LEDoutput2=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, 0, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
   ExpStruct.LEDoutput=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
end

updateAOaxes


% --- Executes on button press in PoissonInjCheck.
function PoissonInjCheck_Callback(hObject, eventdata, handles)
% hObject    handle to PoissonInjCheck (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct cell1 Exp_Defaults
% load('c:\data\Hillel\savedDynClampVector', 'savedDynClampVector');
% ExpStruct.savedDynClampVector = savedDynClampVector;

 ExpStruct.CCoutput1 =alphaConvolve(cell1.pulseamp,0.001,0.005, Exp_Defaults.sweepduration, 0.01, Exp_Defaults.Fs,1000);
 ExpStruct.CCoutput1 = ExpStruct.CCoutput1/Exp_Defaults.CCexternalcommandsensitivity;
 updateAOaxes;
% Hint: get(hObject,'Value') returns toggle state of PoissonInjCheck


% --- Executes on button press in SingleEPSG_check.
function SingleEPSG_check_Callback(hObject, eventdata, handles)
% hObject    handle to SingleEPSG_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of SingleEPSG_check


% --- Executes on button press in PSFtestcheck.
function PSFtestcheck_Callback(hObject, eventdata, handles)
% hObject    handle to PSFtestcheck (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
if get(hObject, 'Value')
    PSFsetup;
else
    close(ExpStruct.MP285struct.PSFplot);
end
% Hint: get(hObject,'Value') returns toggle state of PSFtestcheck


% --- Executes on button press in laserDoseReponseCheck.
function laserDoseReponseCheck_Callback(hObject, eventdata, handles)
% hObject    handle to laserDoseReponseCheck (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
if get(hObject, 'Value')
    doseResponseSetup;
else
    close(ExpStruct.doseResponseStruct.doseResponsePlot);
end

% Hint: get(hObject,'Value') returns toggle state of laserDoseReponseCheck


% --- Executes on button press in digitalLEDcheck.
function digitalLEDcheck_Callback(hObject, eventdata, handles)
% hObject    handle to digitalLEDcheck (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct LED Exp_Defaults
if get(hObject, 'Value')
    ExpStruct.digitalLED_on = 1;
else
    ExpStruct.digitalLED_on = 0;
end
ExpStruct.digitalLEDoutput = makepulseoutputs(LED.pulse_starttime, LED.pulsenumber, LED.pulseduration, ExpStruct.digitalLED_on ,LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
updateAOaxes;
% Hint: get(hObject,'Value') returns toggle state of digitalLEDcheck


% --- Executes on button press in TwoDimMapCheck.
function TwoDimMapCheck_Callback(hObject, eventdata, handles)
% hObject    handle to TwoDimMapCheck (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
if get(hObject, 'Value')
    OneDimMapSetup;
else
  try
    close(ExpStruct.MP285struct.TwoDMapplotCell1);
    close(ExpStruct.MP285struct.TwoDMapplotCell2);
  end
end
% Hint: get(hObject,'Value') returns toggle state of TwoDimMapCheck


% --- Executes on button press in PoissonTrainCheck.
function PoissonTrainCheck_Callback(hObject, eventdata, handles)
% hObject    handle to PoissonTrainCheck (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct LED Exp_Defaults h
if get(hObject, 'Value')
 ExpStruct.LEDoutput=poissonSpikeTrain(Exp_Defaults.sweepduration, Exp_Defaults.Fs, 5, LED.pulseamp, LED.pulseduration);
 ExpStruct.LEDoutput=ExpStruct.LEDoutput';
 ExpStruct.LEDoutput2=ExpStruct.LEDoutput;
 % keep shutter open the whole trial
 ExpStruct.shutterTriggerOutput=makepulseoutputs(1,1, Exp_Defaults.sweepduration*Exp_Defaults.Fs, 5, 1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
  if get(h.digitalLEDcheck,'Value')
    ExpStruct.digitalLEDoutput=ExpStruct.LEDoutput; ExpStruct.digitalLEDoutput(ExpStruct.digitalLEDoutput==LED.pulseamp)=1;
  end 
else
    ExpStruct.LEDoutput=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp+.15, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration, ExpStruct.deltaparam)+LED.DCoffset1; %-.15 for keeping Monaco EOM at 0 mW output
    ExpStruct.LEDoutput2=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration, ExpStruct.deltaparam)+LED.DCoffset2;
    ExpStruct.shutterTriggerOutput=makepulseoutputs(LED.pulse_starttime-10,LED.pulsenumber, LED.pulseduration+15, 5, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
    ExpStruct.digitalLEDoutput = makepulseoutputs(LED.pulse_starttime, LED.pulsenumber, LED.pulseduration, ExpStruct.digitalLED_on ,LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
    ExpStruct.LEDoutput=ExpStruct.LEDoutput;
    ExpStruct.pulsesorramps=0;

end
updateAOaxes;
% Hint: get(hObject,'Value') returns toggle state of PoissonTrainCheck


% --- Executes on button press in storePointButton.
function storePointButton_Callback(hObject, eventdata, handles)
% hObject    handle to storePointButton (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct MP285pointsList

ExpStruct.MP285struct.pointListMapping=1;

if ~isfield(ExpStruct.MP285struct,'StimPoints')
    ExpStruct.MP285struct.StimPoints=nan(1,3); 
end

if ~isnan(ExpStruct.MP285struct.StimPoints(1))
  ExpStruct.MP285struct.StimPoints(size(ExpStruct.MP285struct.StimPoints,1)+1,:)=getPosition(ExpStruct.MP285struct.cam);
else
  ExpStruct.MP285struct.StimPoints(size(ExpStruct.MP285struct.StimPoints,1),:)=getPosition(ExpStruct.MP285struct.cam);
end

ExpStruct.MP285struct.stimOrder = randrepvector(length(ExpStruct.MP285struct.StimPoints), length(ExpStruct.MP285struct.StimPoints), 100);
ExpStruct.MP285struct.TwoDMap.cell1 = NaN(length(ExpStruct.MP285struct.StimPoints),10); 
ExpStruct.MP285struct.TwoDMap.cell2 = NaN(length(ExpStruct.MP285struct.StimPoints),10); 

  % --- Executes on button press in ClearPointsButton.
function ClearPointsButton_Callback(hObject, eventdata, handles)
% hObject    handle to ClearPointsButton (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
 
 ExpStruct.MP285struct.StimPoints=nan(1,3); 


% --- Executes on button press in mappingGuiButton.
function mappingGuiButton_Callback(hObject, eventdata, handles)
global cellMappingGUI
cellMappingGUI = guihandles(CellMapping);
cellMappingSetup;


% --- Executes on button press in galvosCheck.
function galvosCheck_Callback(hObject, eventdata, handles)
% hObject    handle to galvosCheck (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of galvosCheck


% --- Executes on button press in oscillation_check.
function oscillation_check_Callback(hObject, eventdata, handles)
% hObject    handle to oscillation_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of oscillation_check


% --- Executes on button press in BiPOLES_noise_test_check.
function BiPOLES_noise_test_check_Callback(hObject, eventdata, handles)
% hObject    handle to BiPOLES_noise_test_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct cell1 LED
if get(hObject,'Value')==1
    
    ExpStruct.EIratio = 3; 
                    %   generateCorrelatedCurrents(patchCurrentGain, optoGain, currentCorrFactor, optoCorrFactor, EIratio)
    [ExpStruct.I_inj_tot, ExpStruct.BlueInd, ExpStruct.RedInd]=generateCorrelatedCurrents(cell1.pulseamp/75, 1.5, .65, 0,ExpStruct.EIratio);
%     [ExpStruct.I_inj_tot2, ExpStruct.BlueCorr, ExpStruct.RedCorr]=generateCorrelatedCurrents(cell1.pulseamp/35, 1.5, .65, 1,ExpStruct.EIratio);
    ExpStruct.startBiPOLES_corrTest = ExpStruct.sweep_counter;
    
%     mean(ExpStruct.BlueInd)
%     mean(ExpStruct.RedInd)
%     ExpStruct.BiPOLES_dataFig = figure; sgtitle('BiPOLES data');
%     ExpStruct.BiPOLES_dataAxis = gca;
    
    load('storedRealSpikeRates', 'spikeRate');  
    ExpStruct.compareCellSpikeRate = reshape(spikeRate(1:999),9,3,37);
    load('correlatedCurrents', 'correlatedCurrentNoise');
    ExpStruct.correlatedCurrents = correlatedCurrentNoise;
    load('storedStimVetor', 'storedStimVector');
    ExpStruct.stimSequence = storedStimVector; 
    ExpStruct.currentSteps = generateGaussian(cell1.pulseamp, 12, 2,cell1.pulsenumber);
    ExpStruct.BiPOLES_spikeRate = nan(9,3,37);
    ExpStruct.lightLevels = 3;
    ExpStruct.BiPOLES_spikeTimes = nan(ExpStruct.lightLevels, 2,500); 
    ExpStruct.BiPOLES_ISIs = nan(ExpStruct.lightLevels, 2,500); 
    ExpStruct.jitterNoise = rand(1,1000)';
    ExpStruct.stimulus_sequence = randrepvector(ExpStruct.lightLevels,ExpStruct.lightLevels,300);
end


% Hint: get(hObject,'Value') returns toggle state of BiPOLES_noise_test_check
% --- Executes on button press in BiPOLES_parameter_test_check.
function BiPOLES_parameter_test_check_Callback(hObject, eventdata, handles)
% hObject    handle to BiPOLES_parameter_test_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct cell1
if get(hObject,'Value')==1
  ExpStruct.startBiPOLES_calibration = ExpStruct.sweep_counter;
  
  %                                                                               initializeBiPOLES_calibration(offsets,                 gains      steps)
    [ExpStruct.Exp.currentSteps, ExpStruct.BiPOLEScalib.lightVoltages] = initializeBiPOLES_calibration([cell1.pulseamp 0 0], [.5 .2 .1], [ExpStruct.numSteps ExpStruct.numSteps]);
  stimNum=length(ExpStruct.BiPOLEScalib.currentSteps)*length(ExpStruct.BiPOLEScalib.lightVoltages);
  ExpStruct.stimSequence = randrepvector(stimNum, stimNum,80);
  [ExpStruct.CCoutput1, ExpStruct.LEDoutput, ExpStruct.LEDoutput2]=updateBiPOLES_Calibration();
  ExpStruct.CCoutput1 =(ExpStruct.CCoutput1)/cell1.externalcommandsensitivity;
  ExpStruct.calibrationData = nan(length(ExpStruct.BiPOLEScalib.currentSteps),length(ExpStruct.BiPOLEScalib.lightVoltages),10);
  updateAOaxes;

end
% Hint: get(hObject,'Value') returns toggle state of BiPOLES_parameter_test_check

% --- Executes on button press in BiPOLES_calibration_check.
function BiPOLES_calibration_check_Callback(hObject, eventdata, handles)
% hObject    handle to BiPOLES_calibration_check (see GCBO)se
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct cell1 LED
if get(hObject,'Value')==1
  ExpStruct.startBiPOLES_calibration = ExpStruct.sweep_counter;
  ExpStruct.EIratio = 1;
  %                                                                           initializeBiPOLES_calibration(offsets,   gains    steps)
  [ExpStruct.BiPOLEScalib.currentSteps, ExpStruct.BiPOLEScalib.lightVoltages] = initializeBiPOLES_calibration([75 0 0], [1 .3 .15], [3 3]);
%   stimNum=length(ExpStruct.BiPOLEScalib.currentSteps)*length(ExpStruct.BiPOLEScalib.lightVoltages);
%   ExpStruct.stimSequence = randrepvector(stimNum, stimNum,10);
%   stimNum=ExpStruct.numSteps^2; 
%   ExpStruct.stimSequence = randrepvector(stimNum, stimNum,10);
%   ExpStruct.BiPOLES_spikeRate.squarePulse =
%   nan(ExpStruct.numSteps,ExpStruct.numSteps,30); 
% use below lines for square array of red and blue light
%   ExpStruct.BiPOLES_spikeRate.noise = nan(ExpStruct.numSteps,ExpStruct.numSteps,30);
%   ExpStruct.BiPOLES_spikeRate.gamma = nan(ExpStruct.numSteps,ExpStruct.numSteps,30);
%   ExpStruct.BiPOLES_PSD.squarePulse = nan(ExpStruct.numSteps,ExpStruct.numSteps,30);
%   ExpStruct.BiPOLES_PSD.noise = nan(ExpStruct.numSteps,ExpStruct.numSteps,30);
  ExpStruct.BiPOLES_PSD.gamma = nan(ExpStruct.numSteps,ExpStruct.numSteps,30);
% use below lines for a fixed red light and changing blue light
  ExpStruct.BiPOLES_spikeRate.squarePulse = nan(ExpStruct.numSteps,30);
  ExpStruct.BiPOLES_spikeRate.noise = nan(ExpStruct.numSteps,30);
  ExpStruct.BiPOLES_spikeRate.noLight = nan(ExpStruct.numSteps,30);
  ExpStruct.BiPOLES_PSD.squarePulse = nan(ExpStruct.numSteps,30);
  ExpStruct.BiPOLES_PSD.noise = nan(ExpStruct.numSteps,30);
  ExpStruct.BiPOLES_PSD.noLight = nan(ExpStruct.numSteps,30);
%   [ExpStruct.CCoutput1, ExpStruct.LEDoutput, ExpStruct.LEDoutput2]=updateBiPOLES_Calibration();
%   ExpStruct.CCoutput1 =(ExpStruct.CCoutput1)/cell1.externalcommandsensitivity;
%   [ExpStruct.LEDoutput, ExpStruct.LEDoutput2]=BiPOLES_EI_calibrate(LED.pulseamp,LED.pulseamp, 500);  
  ExpStruct.calibrationData = nan(length(ExpStruct.BiPOLEScalib.currentSteps),length(ExpStruct.BiPOLEScalib.lightVoltages),10);
%   [ExpStruct.CCoutput1,ExpStruct.LEDoutput, ExpStruct.LEDoutput2]=BiPOLES_EI_inject(LED.pulseamp, LED.pulseamp*ExpStruct.EIratio, cell1.pulseamp, ExpStruct.numSteps );
    [ExpStruct.LEDoutput, ExpStruct.LEDoutput2]=BiPOLES_inVivo_redBlue2(LED.pulseamp, LED.pulseamp*ExpStruct.EIratio, ExpStruct.numSteps );
  
  updateAOaxes;

end
% Hint: get(hObject,'Value') returns toggle state of BiPOLES_calibration_check


% --- Executes on button press in ASAP_PsChR_check.
function ASAP_PsChR_check_Callback(hObject, eventdata, handles)
% hObject    handle to ASAP_PsChR_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
ExpStruct.startASAP_PsChR_test=ExpStruct.sweep_counter;
% Hint: get(hObject,'Value') returns toggle state of ASAP_PsChR_check
    


% --- Executes on button press in BiPOLES_tuningCurveCheck.
function BiPOLES_tuningCurveCheck_Callback(hObject, eventdata, handles)

global ExpStruct cell1 LED
if get(hObject,'Value')==1
  ExpStruct.startBiPOLES_calibration = ExpStruct.sweep_counter;
  ExpStruct.EIratio = 0.3;
  % defaults has 6 conditions for changing tuning curves for
  % (6+1)*length(currentSteps) stimuli
  %                                                                                                                          initializeBiPOLES_calibration(offsets,--------------------------------gains----------------------------steps)
  [ExpStruct.BiPOLEScalib.currentSteps, ExpStruct.BiPOLEScalib.redLightVoltages, ExpStruct.BiPOLEScalib.blueLightVoltages] = initializeBiPOLES_tuningCurves([0 0 0], [cell1.pulseamp LED.pulseamp LED.pulseamp*ExpStruct.EIratio], 12);
  stimNum=length(ExpStruct.BiPOLEScalib.currentSteps)*8;
  ExpStruct.stimSequence = randrepvector(stimNum, stimNum,10);
  ExpStruct.CCoutput1 =(ExpStruct.CCoutput1)/cell1.externalcommandsensitivity;
  ExpStruct.tuningCurves = nan(length(ExpStruct.BiPOLEScalib.currentSteps),stimNum/length(ExpStruct.BiPOLEScalib.currentSteps),10);
  ExpStruct.BiPOLES_figure = figure;
  updateAOaxes;

end


% --- Executes on slider movement.
function ThreshSlider_Callback(hObject, eventdata, handles)
% hObject    handle to ThreshSlider (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct

ExpStruct.unitThreshold = get(hObject, 'Value');
% Hints: get(hObject,'Value') returns position of slider
%        get(hObject,'Min') and get(hObject,'Max') to determine range of slider


% --- Executes during object creation, after setting all properties.
function ThreshSlider_CreateFcn(hObject, eventdata, handles)
% hObject    handle to ThreshSlider (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: slider controls usually have a light gray background.
if isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor',[.9 .9 .9]);
end


% --- Executes on button press in threshButton.
function threshButton_Callback(hObject, eventdata, handles)
% hObject    handle to threshButton (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct
pos = get(ExpStruct.thresholdLine,'position');
ExpStruct.unitThreshold = pos(3); 


% --- Executes on button press in LED_stay_on_check.
function LED_stay_on_check_Callback(hObject, eventdata, handles)
% hObject    handle to LED_stay_on_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of LED_stay_on_check
