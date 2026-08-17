function varargout = reanalysis2(varargin)
% REANALYSIS2 MATLAB code for reanalysis2.fig
%      REANALYSIS2, by itself, creates a new REANALYSIS2 or raises the existing
%      singleton*.
%
%      H = REANALYSIS2 returns the handle to a new REANALYSIS2 or the handle to
%      the existing singleton*.
%
%      REANALYSIS2('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in REANALYSIS2.M with the given input arguments.
%
%      REANALYSIS2('Property','Value',...) creates a new REANALYSIS2 or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before reanalysis2_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to reanalysis2_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help reanalysis2

% Last Modified by GUIDE v2.5 23-Apr-2015 17:28:36

% Begin initialization code - DO NOT EDIT
gui_Singleton = 1;
gui_State = struct('gui_Name',       mfilename, ...
                   'gui_Singleton',  gui_Singleton, ...
                   'gui_OpeningFcn', @reanalysis2_OpeningFcn, ...
                   'gui_OutputFcn',  @reanalysis2_OutputFcn, ...
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


% --- Executes just before reanalysis2 is made visible.
function reanalysis2_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to reanalysis2 (see VARARGIN)

% Choose default command line output for reanalysis2
handles.output = hObject;

% Update handles structure
guidata(hObject, handles);

% UIWAIT makes reanalysis2 wait for user response (see UIRESUME)
% uiwait(handles.figure1);


% --- Outputs from this function are returned to the command line.
function varargout = reanalysis2_OutputFcn(hObject, eventdata, handles) 
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.output;


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


% --- Executes during object creation, after setting all properties.
function analsyis_popup_CreateFcn(hObject, eventdata, handles)

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in previoussweep_button.
function previoussweep_button_Callback(hObject, eventdata, handles)

global h ExpStruct Exp_Defaults sweeps
if ExpStruct.SetSweepNumber > 1
 ExpStruct.SetSweepNumber=ExpStruct.SetSweepNumber-1;
 update_renanalysis_sweep()
end




% --- Executes on button press in nextsweep_button.
function nextsweep_button_Callback(hObject, eventdata, handles)
% hObject    handle to nextsweep_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct Exp_Defaults sweeps h 
if ExpStruct.SetSweepNumber < size(sweeps,2)
 ExpStruct.SetSweepNumber=ExpStruct.SetSweepNumber+1;
 update_renanalysis_sweep()
end


function SetSweepNumber_Callback(hObject, eventdata, handles)

global h ExpStruct Exp_Defaults sweeps

ExpStruct.SetSweepNumber=str2double(get(hObject,'String'));
update_renanalysis_sweep()

  
% --- Executes during object creation, after setting all properties.
function SetSweepNumber_CreateFcn(hObject, eventdata, handles)

global ExpStruct
% SetSweepNumber=ExpStruct.SetSweepNumber;
% SetSweepNumber=1;
% set(hObject,'String',num2str(SetSweepNumber));

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function LoadPath_Callback(hObject, eventdata, handles)
global RA_Struct
RA_Struct.LoadPath=(get(hObject,'String'));


% --- Executes during object creation, after setting all properties.
function LoadPath_CreateFcn(hObject, eventdata, handles)

global RA_Struct
set(hObject,'String',RA_Struct.LoadPath);

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function ExperimentName_Callback(hObject, eventdata, handles)
global RA_Struct

RA_Struct.ExperimentName=(get(hObject,'String'));
% RA_Struct.SaveName=strcat(RA_Struct.LoadPath,RA_Struct.ExperimentName);

function ExperimentName_CreateFcn(hObject, eventdata, handles)

global ExpStruct % ExperimentName
% set(hObject,'String',ExpStruct.ExperimentName);

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function current_sweep_number_Callback(hObject, eventdata, handles)
% hObject    handle to current_sweep_number (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of current_sweep_number as text
%        str2double(get(hObject,'String')) returns contents of current_sweep_number as a double


% --- Executes during object creation, after setting all properties.
function current_sweep_number_CreateFcn(hObject, eventdata, handles)

global ExpStruct
% set(hObject,'String',num2str(ExpStruct.sweep_counter));

if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in hold_sweep_display_axes.
function hold_sweep_display_axes_Callback(hObject, eventdata, handles)

global h
hold(h.sweep_display_axes);


% --- Executes on button press in record_cell2_check.
function record_cell2_check_Callback(hObject, eventdata, handles)
% hObject    handle to record_cell2_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of record_cell2_check


% --- Executes on button press in Highpass_check.
function Highpass_check_Callback(hObject, eventdata, handles)
% hObject    handle to Highpass_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of Highpass_check


% --- Executes on selection change in popupmenu3.
function popupmenu3_Callback(hObject, eventdata, handles)
% hObject    handle to popupmenu3 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = cellstr(get(hObject,'String')) returns popupmenu3 contents as cell array
%        contents{get(hObject,'Value')} returns selected item from popupmenu3


% --- Executes during object creation, after setting all properties.
function popupmenu3_CreateFcn(hObject, eventdata, handles)
% hObject    handle to popupmenu3 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in radiobutton1.
function radiobutton1_Callback(hObject, eventdata, handles)
% hObject    handle to radiobutton1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of radiobutton1


% --- Executes on button press in radiobutton2.
function radiobutton2_Callback(hObject, eventdata, handles)
% hObject    handle to radiobutton2 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of radiobutton2


% --- Executes on button press in pushbutton7.
function pushbutton7_Callback(hObject, eventdata, handles)
% hObject    handle to pushbutton7 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)


% --- Executes on button press in SaveExperiment_button.
function SaveExperiment_button_Callback(hObject, eventdata, handles)
% hObject    handle to SaveExperiment_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global RA_Struct sweeps Exp_Defaults ExpStruct LED Ramp cell1 cell2
button=questdlg('Are you sure?');
% savepath = strcat(RA_Struct.LoadPath, 'reanalysis\');
savename = strcat(RA_Struct.LoadPath, RA_Struct.ExperimentName);
if strcmp(button, 'Yes')
    % save everything

    save(savename,'ExpStruct','-append'); 
end

% --- Executes on button press in loadexp_button.
function loadexp_button_Callback(hObject, eventdata, handles)
% clear all
global  RA_Struct h MStimHandles

loadname=strcat(RA_Struct.LoadPath,RA_Struct.ExperimentName); 


load(loadname, 'sweeps', 'Exp_Defaults', 'ExpStruct', 'cell1', 'cell2'); %, 'motor'); 
% plot
	

% plot(h.Whole_cell1_axes_Rs,cell1.series_r,'o');
ylabel(h.Whole_cell1_axes_Rs, 'MOhm');
plot(h.Whole_cell1_axes_Ih,cell1.holding_i,'o');
ylabel(h.Whole_cell1_axes_Ih, 'pA');
plot(h.LEDoutput_axes,ExpStruct.timebase, ExpStruct.LEDoutput);
ylabel(h.LEDoutput_axes, 'V');
plot(h.CCoutput_axes,ExpStruct.timebase, ExpStruct.CCoutput1, ExpStruct.timebase, ExpStruct.CCoutput2);

value3 = get(h.record_cell2_check, 'Value');

set(h.current_sweep_number,'String',num2str(ExpStruct.sweep_counter));
ExpStruct.SetSweepNumber = 1;
set(h.SetSweepNumber,'String',num2str(1));
temp = sweeps{1}; temp = temp(:,1); timebase = linspace(1,length(temp)/Exp_Defaults.Fs*1000, length(temp));
plot(h.sweep_display_axes, ExpStruct.timebase, temp); 
% updateAOaxes;   

% remove skipped_sweeps array
if (isfield(ExpStruct, 'skipped_sweeps'))
   set (h.skip_sweeps_table, 'Data', ExpStruct.skipped_sweeps);
else
   set (h.skip_sweeps_table, 'Data', []);
   ExpStruct.skipped_sweeps = [];
end

% % update Expt_Params in GUI. Use catch statements to avoid errors if each
% field wasn't filled in during an experiment.
try
    set(h.genotype,'String',(ExpStruct.Expt_Params.genotype));
catch
    set(h.genotype,'String',('n/a'));
end

try
    set(h.age,'String',(ExpStruct.Expt_Params.age));
catch
    set(h.age,'String',('n/a'));
end

try
    set(h.virus,'String',(ExpStruct.Expt_Params.virus));
catch
    set(h.virus,'String',('n/a'));
end

try
    set(h.internal,'String',(ExpStruct.Expt_Params.internal));
catch 
     set(h.internal,'String',('n/a'));
end

try
    set(h.brainregion,'String',(ExpStruct.Expt_Params.brainregion));
catch
     set(h.brainregion,'String',('n/a'));
end
    
try    
    set(h.animal_number,'String',(ExpStruct.Expt_Params.animal_number));
catch
     set(h.animal_number,'String',('n/a'));    
end

try
    set(h.lightsource,'String',(ExpStruct.Expt_Params.lightsource));
catch
    set(h.lightsource,'String',('n/a'));
end
%     set(h.leftmeasure, 'String', ExpStruct.TuningStruct.leftmeasure);
%     set(h.rightmeasure, 'String', ExpStruct.TuningStruct.rightmeasure);

try
    set(h.cell_depth,'String',(ExpStruct.Expt_Params.cell_depth));
catch
    set(h.cell_depth,'String',('n/a'));
end


set(h.current_sweep_number, 'String', ExpStruct.sweep_counter);
   
try 
    set(h.exc_left_limit, 'String', ExpStruct.RAlimits.exc_left_limit);
    set(h.exc_right_limit, 'String', ExpStruct.RAlimits.exc_right_limit);
   
catch 
       
    set(h.exc_left_limit, 'String', []);
    set(h.exc_right_limit, 'String', []);
end
try
    set(h.inh_left_limit, 'String', ExpStruct.RAlimits.inh_left_limit);
    set(h.inh_right_limit, 'String', ExpStruct.RAlimits.inh_right_limit);
catch
    set(h.inh_left_limit, 'String', []);
    set(h.inh_right_limit, 'String', []);
end

try 
    set(MStimHandles.ExcitationLeftLimit, 'String', ExpStruct.RAlimits.MStim.ExcitationLeftLimit);
    set(MStimHandles.ExcitationRightLimit, 'String', ExpStruct.RAlimits.MStim.ExcitationRightLimit);
    set(MStimHandles.InhibitionLeftLimit, 'String', ExpStruct.RAlimits.MStim.InhibitionLeftLimit);
    set(MStimHandles.InhibitionRightLimit, 'String', ExpStruct.RAlimits.MStim.InhibitionRightLimit);
    set(MStimHandles.VmLeftLimit, 'String', ExpStruct.RAlimits.MStim.VmLeftLimit);
    set(MStimHandles.VmRightLimit, 'String', ExpStruct.RAlimits.MStim.VmRightLimit);
catch

end

globalizeVariables;
% update other params
% val=get(h.Cell2_type_popup,'value');
% set(h.Cell2_type_popup,val);




% --- Executes on button press in Save_and_Close_button.
function Save_and_Close_button_Callback(hObject, eventdata, handles)
% hObject    handle to Save_and_Close_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)



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



function sweep_time_Callback(hObject, eventdata, handles)
% hObject    handle to sweep_time (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of sweep_time as text
%        str2double(get(hObject,'String')) returns contents of sweep_time as a double


% --- Executes during object creation, after setting all properties.
function sweep_time_CreateFcn(hObject, eventdata, handles)
% hObject    handle to sweep_time (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

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


% --- Executes on selection change in popupmenu4.
function popupmenu4_Callback(hObject, eventdata, handles)
% hObject    handle to popupmenu4 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = cellstr(get(hObject,'String')) returns popupmenu4 contents as cell array
%        contents{get(hObject,'Value')} returns selected item from popupmenu4


% --- Executes during object creation, after setting all properties.
function popupmenu4_CreateFcn(hObject, eventdata, handles)
% hObject    handle to popupmenu4 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in store_skipped_exc_sweep.
function store_skipped_exc_sweep_Callback(hObject, eventdata, handles)
% hObject    handle to store_skipped_exc_sweep (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct h

if ~(isfield(ExpStruct, 'skipped_sweeps'))
    ExpStruct.skipped_sweeps = [];
end
sz=size(ExpStruct.skipped_sweeps,1);
ExpStruct.skipped_sweeps(sz+1,1)=ExpStruct.SetSweepNumber; 
set (h.skip_sweeps_table, 'Data', ExpStruct.skipped_sweeps);



% --- Executes on button press in store_skipped_inh_sweep.
function store_skipped_inh_sweep_Callback(hObject, eventdata, handles)
% hObject    handle to store_skipped_inh_sweep (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct h

if ~(isfield(ExpStruct, 'skipped_sweeps'))
    ExpStruct.skipped_sweeps = zeros(1,2);
end
sz=size(ExpStruct.skipped_sweeps,1);
ExpStruct.skipped_sweeps(sz+1,2)=ExpStruct.SetSweepNumber; 
set (h.skip_sweeps_table, 'Data', ExpStruct.skipped_sweeps);


% --- Executes on button press in zero_trace_check.
function zero_trace_check_Callback(hObject, eventdata, handles)
% hObject    handle to zero_trace_check (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of zero_trace_check


% --- Executes on button press in plotTraces_button.
function plotTraces_button_Callback(hObject, eventdata, handles)
% hObject    handle to plotTraces_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)


% --- Executes on button press in plotTuning_button.
function plotTuning_button_Callback(hObject, eventdata, handles)
% hObject    handle to plotTuning_button (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
plotTuning;

% --- Executes on button press in plotopto_tuning.
function plotopto_tuning_Callback(hObject, eventdata, handles)
% hObject    handle to plotopto_tuning (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
plot_opto_tuning;

% --- Executes on button press in avg_alt_exc_traces.
function avg_alt_exc_traces_Callback(hObject, eventdata, handles)

global ExpStruct h

[avg_NL, avg_L] = avg_alt_traces(ExpStruct.RAlimits.exc_left_limit, ExpStruct.RAlimits.exc_right_limit);
plot(h.exc_running_axes, ExpStruct.timebase, avg_NL, 'k', ExpStruct.timebase, avg_L, 'r'); 
% hObject    handle to avg_alt_exc_traces (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)



function exc_left_limit_Callback(hObject, eventdata, handles)
% hObject    handle to exc_left_limit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct 
ExpStruct.RAlimits.exc_left_limit=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of exc_left_limit as text
%        str2double(get(hObject,'String')) returns contents of exc_left_limit as a double


% --- Executes during object creation, after setting all properties.
function exc_left_limit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to exc_left_limit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called
  
% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function exc_right_limit_Callback(hObject, eventdata, handles)
% hObject    handle to exc_right_limit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct 
ExpStruct.RAlimits.exc_right_limit=str2double(get(hObject,'String'));

% Hints: get(hObject,'String') returns contents of exc_right_limit as text
%        str2double(get(hObject,'String')) returns contents of exc_right_limit as a double


% --- Executes during object creation, after setting all properties.
function exc_right_limit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to exc_right_limit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


function inh_left_limit_Callback(hObject, eventdata, handles)
% hObject    handle to inh_left_limit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct 
ExpStruct.RAlimits.inh_left_limit=str2double(get(hObject,'String'));

% Hints: get(hObject,'String') returns contents of inh_left_limit as text
%        str2double(get(hObject,'String')) returns contents of inh_left_limit as a double


% --- Executes during object creation, after setting all properties.
function inh_left_limit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to inh_left_limit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function inh_right_limit_Callback(hObject, eventdata, handles)
% hObject    handle to inh_right_limit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct 
ExpStruct.RAlimits.inh_right_limit=str2double(get(hObject,'String'));

% Hints: get(hObject,'String') returns contents of inh_right_limit as text
%        str2double(get(hObject,'String')) returns contents of inh_right_limit as a double


% --- Executes during object creation, after setting all properties.
function inh_right_limit_CreateFcn(hObject, eventdata, handles)
% hObject    handle to inh_right_limit (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function leftmeasure_Callback(hObject, eventdata, handles)
% hObject    handle to leftmeasure (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct 
ExpStruct.TuningStruct.leftmeasure=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of leftmeasure as text
%        str2double(get(hObject,'String')) returns contents of leftmeasure as a double


% --- Executes during object creation, after setting all properties.
function leftmeasure_CreateFcn(hObject, eventdata, handles)
% hObject    handle to leftmeasure (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function rightmeasure_Callback(hObject, eventdata, handles)
% hObject    handle to rightmeasure (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global ExpStruct 
ExpStruct.TuningStruct.rightmeasure=str2double(get(hObject,'String'));
% Hints: get(hObject,'String') returns contents of rightmeasure as text
%        str2double(get(hObject,'String')) returns contents of rightmeasure as a double


% --- Executes during object creation, after setting all properties.
function rightmeasure_CreateFcn(hObject, eventdata, handles)
% hObject    handle to rightmeasure (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


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

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function age_Callback(hObject, eventdata, handles)
% hObject    handle to age (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
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


% --- Executes on button press in checkbox1.
function checkbox1_Callback(hObject, eventdata, handles)
% hObject    handle to checkbox1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of checkbox1



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

% Hints: get(hObject,'String') returns contents of internal as text
%        str2double(get(hObject,'String')) returns contents of internal as a double


% --- Executes during object creation, after setting all properties.
function internal_CreateFcn(hObject, eventdata, handles)
% hObject    handle to internal (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called
global ExpStruct
ExpStruct.Expt_Params.internal=(get(hObject,'String'));   
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



function set_ISI_Callback(hObject, eventdata, handles)
% hObject    handle to set_ISI (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of set_ISI as text
%        str2double(get(hObject,'String')) returns contents of set_ISI as a double


% --- Executes during object creation, after setting all properties.
function set_ISI_CreateFcn(hObject, eventdata, handles)
% hObject    handle to set_ISI (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function edit9_Callback(hObject, eventdata, handles)
% hObject    handle to edit9 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of edit9 as text
%        str2double(get(hObject,'String')) returns contents of edit9 as a double


% --- Executes during object creation, after setting all properties.
function edit9_CreateFcn(hObject, eventdata, handles)
% hObject    handle to edit9 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on selection change in popupmenu1.
function popupmenu1_Callback(hObject, eventdata, handles)
% hObject    handle to popupmenu1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = cellstr(get(hObject,'String')) returns popupmenu1 contents as cell array
%        contents{get(hObject,'Value')} returns selected item from popupmenu1


% --- Executes during object creation, after setting all properties.
function popupmenu1_CreateFcn(hObject, eventdata, handles)
% hObject    handle to popupmenu1 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in checkbox2.
function checkbox2_Callback(hObject, eventdata, handles)
% hObject    handle to checkbox2 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of checkbox2


% --- Executes on button press in checkbox3.
function checkbox3_Callback(hObject, eventdata, handles)
% hObject    handle to checkbox3 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of checkbox3


% --- Executes on button press in checkbox4.
function checkbox4_Callback(hObject, eventdata, handles)
% hObject    handle to checkbox4 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of checkbox4



function Lumencor_color_Callback(hObject, eventdata, handles)
% hObject    handle to Lumencor_color (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of Lumencor_color as text
%        str2double(get(hObject,'String')) returns contents of Lumencor_color as a double


% --- Executes during object creation, after setting all properties.
function Lumencor_color_CreateFcn(hObject, eventdata, handles)
% hObject    handle to Lumencor_color (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in checkbox5.
function checkbox5_Callback(hObject, eventdata, handles)
% hObject    handle to checkbox5 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hint: get(hObject,'Value') returns toggle state of checkbox5



function edit11_Callback(hObject, eventdata, handles)
% hObject    handle to edit11 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of edit11 as text
%        str2double(get(hObject,'String')) returns contents of edit11 as a double


% --- Executes during object creation, after setting all properties.
function edit11_CreateFcn(hObject, eventdata, handles)
% hObject    handle to edit11 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on selection change in Cell1_type_popup.
function Cell1_type_popup_Callback(hObject, eventdata, handles)
% hObject    handle to Cell1_type_popup (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: contents = cellstr(get(hObject,'String')) returns Cell1_type_popup contents as cell array
%        contents{get(hObject,'Value')} returns selected item from Cell1_type_popup


% --- Executes during object creation, after setting all properties.
function Cell1_type_popup_CreateFcn(hObject, eventdata, handles)
% hObject    handle to Cell1_type_popup (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: popupmenu controls usually have a white background on Windows.
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


% --- Executes on button press in avg_alt_inh_traces.
function avg_alt_inh_traces_Callback(hObject, eventdata, handles)
global ExpStruct h 
[avg_NL, avg_L] = avg_alt_traces(ExpStruct.RAlimits.inh_left_limit, ExpStruct.RAlimits.inh_right_limit); 
plot(h.inh_running_axes, ExpStruct.timebase, avg_NL, 'k', ExpStruct.timebase, avg_L, 'r'); 
% hObject    handle to avg_alt_inh_traces (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)


% --- Executes on button press in openMStimReanalysis.
function openMStimReanalysis_Callback(hObject, eventdata, handles)
% hObject    handle to openMStimReanalysis (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
setup_RA_MStim
