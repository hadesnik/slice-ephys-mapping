 


function acquire ()
% this is the core function of acquisition. It is called by the timer
% function when triggering internally, and is the re-called for each
% trigger when using external triggers

%call globals
global cell1 cell2 LED Ramp ExpStruct Exp_Defaults h sweeps s cellMappingGUI sweeps_DI
%assign local names for varoius variables (for convenience)
testpulse=ExpStruct.testpulse; LEDoutput=ExpStruct.LEDoutput; LEDoutput2=ExpStruct.LEDoutput2;
CCoutput1=ExpStruct.CCoutput1; CCoutput2=ExpStruct.CCoutput2;
thissweep=ExpStruct.thissweep; cell1sweep=ExpStruct.cell1sweep;
cell2sweep=ExpStruct.cell2sweep; DIOsweep = ExpStruct.DIOsweep;
stims=ExpStruct.stims; sweep_counter=ExpStruct.sweep_counter;
% create outgoing digital trigger for external devices, such as ScanImage


%% generate analog output vectors for each trial
[AO0 AO1 AO2 AO3] = analogoutput_gen();


% queue output analog and digital data
if Exp_Defaults.demoDAQ ~= 1 % use for a demo Daq when not connected to a real DAQ

    
%   s.queueOutputData([ExpStruct.shutterTriggerOutput ExpStruct.Lumencor_output ExpStruct.shutterTriggerOutput AO0 AO1 AO2 AO3 ]);
  s.queueOutputData([ AO0 AO1 AO2 AO3 ]);

  % if triggering is external set timeout to 180 seconds
  if (Exp_Defaults.ExternalTrigger == 1)
      s.ExternalTriggerTimeout = 180;
  end

  %start analog scanning and collect the data from the DAQ buffer into data.
  % this is the core of the DAQ process
  data = s.startForeground();

else % for demo daq
  fakeData = normrnd(0, 5, length(ExpStruct.timebase), 3);
  if isfield(ExpStruct, 'compareCellSpikeRate')
     randNumSpikes = ExpStruct.compareCellSpikeRate(ExpStruct.sweep_counter);
  else
     randNumSpikes = fix(normrnd(20, 4)); 
  end
  randSpikeTimes = rand(randNumSpikes,1); 
  fakeData(fix(randSpikeTimes*Exp_Defaults.Fs)) = -40; 
  pause(0.1);
    
end

%store channels 1 and 2 in thissweep for further processing
thissweep=data(:,1:3);
thissweep_DI=downsample(data(:,1:10),10); 
% thissweep=fakeData(:,1:2);
ExpStruct.temperature(ExpStruct.sweep_counter) = data(1,3)*10; % assumes temperature sensor is on AO2 (channel 3). Output from Warner is 100 mV/C. 

% store the data in cell array 'sweeps'
sweeps{sweep_counter}=thissweep;
sweeps_DI{sweep_counter}=thissweep_DI; 
    
% scale units
if Exp_Defaults.demoDAQ ~= 1
 
  thissweep(:,1)=thissweep(:,1)*1000; % scale from nA to pA or Volts to mV

% scale by user gain for each channel
  thissweep(:,1)=thissweep(:,1)/cell1.user_gain; 
  thissweep(:,2)=thissweep(:,2)/cell2.user_gain;
end 
% store Vhold from MultiClamp on secodary output when in Vclamp. Vhold is
% on channel AI2
ExpStruct.Vhold(ExpStruct.sweep_counter) = fix(data(1,3)*1000/20);


% if using dynamic clamp on cell1 one store data on analog input 3 as
% membrane current
if (strcmp(Exp_Defaults.AO0,'dynamicClamp')==1) 
 membraneCurrent = data(:,4); % store membrane current from cell1 (dynamically clamped pipette)
 thissweep(:,3)= membraneCurrent*1000; % scale to pA, assume scale factor of 1V/nA
 membraneVoltage = data(:,5); % store membrane voltage from cell2 (voltage clamped pipette)
 ExpStruct.Vhold(ExpStruct.sweep_counter) = fix(data(1,5)*1000/20);

end




%% store and process the data from the digital inputs line 29:31
if Exp_Defaults.DIO_on == 1 && Exp_Defaults.demoDAQ~=1
    DIOsweep = data(:,4:13);
    DIOsweep = circshift(DIOsweep,-2,2); % hack because of wiring of channels from pp from visstim pc to NIDAQ
%     DIO = data(:,4:11); % extract the digital input channels. The highest channel (channel 9) is wired to accept triggers. HAA 1/21/15
%     DIO2 = data(:,4:11);
    intDIO = int16(DIOsweep); % convert to unsigned integer to save memory
    [stimTimes stimSeq] = getStimNums(intDIO);
%     stimSeq
    ExpStruct.VisStims{sweep_counter} = stimSeq;
    ExpStruct.VisStimTimes{sweep_counter} = stimTimes;
%     thisSeq = ExpStruct.VisStims{sweep_counter};
%     DIO = DIO(1,:);
%     DIO = DIO(end:-1:1); % reverse the vector 
%     ExpStruct.VisStimSeq(sweep_counter)=binaryVectorToDecimal(DIO); % convert binary to decimal
%     binaryVectorToDecimal(DIO);
%     ExpStruct.VisStimSeq(sweep_counter)=(ExpStruct.VisStims{sweep_counter}-1)/2;
end




%% store the analog outputs, but downsample them
% note: because sweep_coutner is not incremented, this results in a
% frameshift of one trial between the stim and the acquisition

ExpStruct.stims{sweep_counter}={(downsample(LEDoutput,10)), downsample(LEDoutput2, 10), downsample(CCoutput1,10), downsample(CCoutput2,10), downsample(ExpStruct.digitalLEDoutput,10), downsample(ExpStruct.Lumencor_output,10)};
set(h.current_sweep_number,'String',num2str(sweep_counter));
ExpStruct.cell1sweep=thissweep(:,1);
ExpStruct.cell2sweep=thissweep(:,2);

%% high pass sweeps if checked
value4 = get(h.Highpass_check, 'Value');

if (value4 == 1)
    ExpStruct.cell1sweep=highpass_filter(ExpStruct.cell1sweep);
   % ExpStruct.cell2sweep=highpass_filter(ExpStruct.cell2sweep);
end

%after data collection analzye inputs for series_r and other properties
analyze_series_r(ExpStruct.cell1sweep, ExpStruct.cell2sweep)

%after data collection compute spikes per second
if (value4 == 1)
  [ height, spiketimes, num_spikes ] =   getIclampSpikeTimes(sweeps{ExpStruct.sweep_counter}, 1/Exp_Defaults.Fs, length(ExpStruct.timebase)/Exp_Defaults.Fs,'lp');
else
  [ height, spiketimes, num_spikes ] =   getIclampSpikeTimes(sweeps{ExpStruct.sweep_counter}, 1/Exp_Defaults.Fs, length(ExpStruct.timebase)/Exp_Defaults.Fs,'Vm');
end

cell1.spikerate1(ExpStruct.sweep_counter) = num_spikes;

    
%% stores absolute time when first sweep is taken
if ExpStruct.sweep_counter == 1
   ExpStruct.exp_start_time = clock;
   ExpStruct.trialtime(ExpStruct.sweep_counter)= 0;
end

% if not first trial store elapsed time to current trial
currenttime = clock;
elapsed_time = etime(currenttime, ExpStruct.exp_start_time);
elapsed_time_in_minutes = elapsed_time/60; % convert to minutes
ExpStruct.trialtime(ExpStruct.sweep_counter) = elapsed_time_in_minutes;

% draw current experiment time in whole cell1 axes
mins = floor(elapsed_time_in_minutes); % get minutes
secs = elapsed_time_in_minutes - mins;
secs = round(secs*60); % convert back to seconds
mins = num2str(mins);
 if (secs>9)
  secs = num2str(secs);
 else
  secs = num2str(secs);
  secs = strcat('0',secs);
 end
current_sweep_time = strcat(mins,':', secs);
% 	
%% increment sweep counter
ExpStruct.sweep_counter=ExpStruct.sweep_counter+1; 


%% autogenerate current injection steps if checked
value1 = get(h.autogen_cell1_check, 'Value');
value2 = get(h.autogen_cell2_check, 'Value');

% test if should plot data from channel2
value3 = get(h.record_cell2_check, 'Value');

if (value1 == 1 || value2 == 1)
   autogenerate_cc_steps
end

%% check if automatically updating an AO stimulus parameter, select the
% parameter, update it, and generate new AO vectors for next trial
% not finished yet 4/30/2015


if get(h.auto_update_param_check, 'Value')
    type=h.update_param_popup.String{get(h.update_param_popup,'value')};
    switch type
        case 'frequency'
          nextPulseFrequency = ExpStruct.testPulseFrequencies(ExpStruct.stimOrder(ExpStruct.sweep_counter));
         
    ExpStruct.LEDoutput=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp,  nextPulseFrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
    set(h.pulsefrequency,'String', nextPulseFrequency);

    %     [updated_param, type] = auto_update_param(ExpStruct.sweep_counter, ExpStruct.deltaparam, 10);
    %     if (strcmp(type, 'pulse duration')) || (strcmp(type, 'pulse amplitude'))
% %     ExpStruct.piezooutput = make_ramp_and_hold( LED.pulse_starttime,LED.pulsenumber, LED.pulseduration,LED.pulseamp,...
% %         LED.pulsefrequency,     Ramp.rampstart_voltage, LED.pulseamp, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
%     ExpStruct.LEDoutput=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
%     else
%          ExpStruct.piezooutput = makecosineoutputs( LED.pulse_starttime,LED.pulsenumber, LED.pulseduration,LED.pulseamp,...
%         LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
    end
    % store the updated parameter
%     ExpStruct.VisStimSeq(ExpStruct.sweep_counter)=updated_param;
    updateAOaxes
    
end

%% do post trial analysis for cell1

% if (get(h.addcursors_radio,'Value')==1)
% if isfield(ExpStruct,'analysis_limits')
%     output1=analyze_wholecell(1); 
%     ExpStruct.runningplot1(ExpStruct.sweep_counter-1)=output1; % -1 b/c analsyis comes after incrementing the sweep counter
%     plot(h.analysis1_axes, ExpStruct.trialtime, ExpStruct.runningplot1, 'o'); 
% end
% if (get(h.addcursors_radio2,'Value')==1)
%     output2=analyze_wholecell(2); 
%     ExpStruct.runningplot2(ExpStruct.sweep_counter-1)=output2; % -1 b/c analsyis comes after incrementing the sweep counter
%     plot(h.analysis1_axes, ExpStruct.trialtime, ExpStruct.runningplot2, 'o'); 
% end

% check if holding axes and stores limits
val5 = get(h.wholecell1_axes_hold_check, 'Value'); 
if (val5 == 1) % if checked get current axes limits
    xlimits = get(h.Whole_cell1_axes,'xlim');
    ylimits = get(h.Whole_cell1_axes, 'ylim');
end

%% plot the data on the corresponding axes in the GUI figure
% plot asterisks for each detected spike (threshold crossing)
value4 = get(h.Highpass_check, 'Value');
% if (value4 == 1)
%     plot(h.Whole_cell1_axes, ExpStruct.timebase,ExpStruct.cell1sweep,spiketimes, height,'*r'); 
%     
% else
ylimits = get(h.Whole_cell1_axes, 'YLim');
% try    plot(h.Whole_cell1_axes,ExpStruct.timebase,ExpStruct.cell1sweep, spiketimes, height,'*r');
%     catch
       plot(h.Whole_cell1_axes,ExpStruct.timebase,ExpStruct.cell1sweep);
% end
    xlim(h.Whole_cell1_axes,[0 Exp_Defaults.sweepduration]);
% end



if val5 == 1 % if holding axes limits
    xlim(h.Whole_cell1_axes, [xlimits(1) xlimits(2)]);
    ylim(h.Whole_cell1_axes, [ylimits(1) ylimits(2)]);
end


plotyy(h.Whole_cell1_axes_Ih, ExpStruct.trialtime, cell1.holding_i, ExpStruct.trialtime, ExpStruct.temperature);

val = get(h.Highpass_check, 'Value'); % check for highpass filtering
if (val == 1)
   plot(h.Whole_cell1_axes_Rs, ExpStruct.trialtime, cell1.spikerate1,'o');
   ylim(h.Whole_cell1_axes_Rs, [0 60]);
   % draw spike treshold line
   xlimits = get(h.Whole_cell1_axes, 'XLim');
   ylimits = get(h.Whole_cell1_axes, 'YLim');
   if ExpStruct.unitThreshold 
      ExpStruct.thresholdLine = drawline(h.Whole_cell1_axes, 'color', 'red', 'position', [0 ExpStruct.unitThreshold; xlimits(2) ExpStruct.unitThreshold]);
   else % if threshold is zero from initialization
        ExpStruct.thresholdLine = drawline(h.Whole_cell1_axes, 'color', 'red', 'position', [0 ylimits(1); xlimits(2) ylimits(1)]);
   end
else
   plot(h.Whole_cell1_axes_Rs, ExpStruct.trialtime, cell1.series_r,'o');
end

plot(h.Whole_cell1_axes_Ir, ExpStruct.trialtime, cell1.input_r,'o')


%% keep cursor lines on if checked % comment out to prevent cursur update
% if (get(h.addcursors_radio,'Value')==1)
%     dualcursor([ExpStruct.analysis_limits.cell1(1) ExpStruct.analysis_limits.cell1(3)],[],[],[],h.Whole_cell1_axes); 
% end
% if (get(h.addcursors_radio2,'Value')==1)
%      dualcursor([ExpStruct.analysis_limits.cell2(1) ExpStruct.analysis_limits.cell2(3)],[],[],[],h.Whole_cell1_axes); 
% end

if (value3 == 1) % if recording two cells
    plot(h.Whole_cell2_axes,ExpStruct.timebase,ExpStruct.cell2sweep);%-mean(ExpStruct.cell2sweep(1:100)));%, ExpStruct.timebase, -1*thissweep(:,3)); 
    xlim(h.Whole_cell2_axes,[0 Exp_Defaults.sweepduration]);
    plot(h.Whole_cell2_axes_Ih,cell2.holding_i,'o');
    plot(h.Whole_cell2_axes_Rs,cell2.series_r,'o');
    plot(h.Whole_cell2_axes_Ir,cell2.input_r,'o');
    
end
val=(get(h.Cell1_type_popup, 'Value'));
if (val == 3) % if LFP 1, plot non-filtered version in axes for cell2
    plot(h.Whole_cell2_axes, ExpStruct.timebase,thissweep(:,1));
end

labelaxes()

%% check if default saving checkbox is checked, otherwise don't save; when
% using external triggering avoid saving after each trial because saving
% can cause acquisition to miss triggers

saveval =  get(h.default_save_check, 'Value');
if (saveval==1)
    save(ExpStruct.SaveName);
end

%% move Sutter MP285 if mapping
if get(h.PSFtestcheck,'value') && Exp_Defaults.demoDAQ~=1 && get(h.laserDoseReponseCheck, 'Value')~=1
    ExpStruct.currentPosition{ExpStruct.sweep_counter} = getPosition(ExpStruct.MP285struct.cam);
    suttermove
%     updatePSFplot(thissweep, 'peakCurrent');
      updatePSFplot(thissweep,'spikes'); 
end

%% check if performing laser dose response curve
if get(h.laserDoseReponseCheck, 'Value') && ~get(h.PSFtestcheck,'value')
    updateDoseReponseCurve(thissweep);
end    

if get(h.laserDoseReponseCheck, 'Value') && get(h.PSFtestcheck,'value') 
   updatePSF_DRC(thissweep,'peakCurrent'); 
%    updatePSF_DRC(thissweep,'spikes'); 
   suttermove
end

%% compute PSF tuning functions
if get(h.TwoDimMapCheck,'value') 
   ExpStruct.currentPosition{ExpStruct.sweep_counter} = getPosition(ExpStruct.MP285struct.cam);
   update1DMapplot(thissweep);
   pause(.05)
   suttermove
   
end 
    
%% check if doing cell mapping
try
 if get(cellMappingGUI.mapCheck, 'value')
     updateCellMappingPlot(thissweep);
      nextPower = ExpStruct.MP285struct.stimPowers(ExpStruct.MP285struct.stimPowerOrder(ExpStruct.sweep_counter));
       ExpStruct.LEDoutput2=makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, nextPower,  LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
    suttermove
    updateAOaxes;
 end
end 
%% check if switching LED on and off
val_LED_state = get(h.Alt_LED_state, 'Value');
if (val_LED_state==1)
    % 8/2/22 changes to turn OFF LED every 10th trial for persistent
    % optogenetic silencing experiment
   if (mod(ExpStruct.sweep_counter-1,3  )==1) % if even numbered trial
        ExpStruct.LEDoutput = makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration); 
        ExpStruct.LEDoutput2 = makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, LED.pulseamp, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration); 

      
        %          ExpStruct.LEDoutput = make_ramps (Ramp.rampstart_time, Ramp.ramp_duration, Ramp.ramp_frequency, Ramp.ramp_number, Ramp.rampstart_voltage, Ramp.rampend_voltage, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
        ExpStruct.LED_state(ExpStruct.sweep_counter-1)=0;
        ExpStruct.Lumencor_output = Digital_outputgen( LED.color , LED.pulse_starttime, LED.pulsenumber, LED.pulseduration,LED.pulsefrequency );

            updateAOaxes
        
   else % turn off output to LEDs
        ExpStruct.LEDoutput = makepulseoutputs(LED.pulse_starttime,LED.pulsenumber, LED.pulseduration, 0, LED.pulsefrequency, Exp_Defaults.Fs, Exp_Defaults.sweepduration); % Subtract -1 V to keep laser off for Shanghai lasers
        ExpStruct.LED_state(ExpStruct.sweep_counter-1)=1;
        ExpStruct.Lumencor_output = ones(Exp_Defaults.Fs*Exp_Defaults.sweepduration,6);
%         ExpStruct.LEDoutput2 =ones(length(ExpStruct.timebase),1)*LED.pulseamp2;
        ExpStruct.LEDoutput2 =zeros(length(ExpStruct.timebase),1);
        updateAOaxes
   end
end

if get(h.LED_stay_on_check,'value')
   ExpStruct.LEDoutput =ones(length(ExpStruct.timebase),1)*LED.pulseamp;
   ExpStruct.LEDoutput2 =ones(length(ExpStruct.timebase),1)*LED.pulseamp2;
   
else
     ExpStruct.LED_state(ExpStruct.sweep_counter-1)=0;
end

%% update Poisson Train if using
if get(h.PoissonTrainCheck, 'Value')
    ExpStruct.LEDoutput=poissonSpikeTrain(Exp_Defaults.sweepduration, Exp_Defaults.Fs, 5, LED.pulseamp, LED.pulseduration);
    ExpStruct.LEDoutput=ExpStruct.LEDoutput';
    ExpStruct.LEDoutput2=ExpStruct.LEDoutput;
    % keep shutter open the whole trial
    ExpStruct.shutterTriggerOutput=makepulseoutputs(1,1, Exp_Defaults.sweepduration*Exp_Defaults.Fs, 5, 1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
   if get(h.digitalLEDcheck,'Value')
    ExpStruct.digitalLEDoutput=ExpStruct.LEDoutput; ExpStruct.digitalLEDoutput(ExpStruct.digitalLEDoutput==LED.pulseamp)=1;
   end 
    updateAOaxes;
end

%% update Multi-color LED Lumencor Poisson noise


if get(h.MultiLED_check, 'Value')
    [blueOutput] = gammaCurrentInj(LED.pulseamp,.01, 0, cell2.pulsefrequency, 0, 0, 0,  ExpStruct.timebase, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
    [redOutput] = gammaCurrentInj(LED.pulseamp2,.01, 0, cell2.pulsefrequency, 0, 0, 0,  ExpStruct.timebase, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
%     digBlueOutput = -1*(A2D(blueOutput,LED.pulseamp)-1); % for Lumencor
%     digRedOutput = -1*(A2D(redOutput,LED.pulseamp)-1); % for Lumencor
    ExpStruct.LEDoutput=zeros(length(ExpStruct.timebase),1);
    ExpStruct.LEDoutput2=zeros(length(ExpStruct.timebase),1);
    
    ExpStruct.LEDoutput(Ramp.rampstart_time*(Exp_Defaults.Fs/1000):Ramp.rampend_time*(Exp_Defaults.Fs/1000))=blueOutput(Ramp.rampstart_time*(Exp_Defaults.Fs/1000):Ramp.rampend_time*(Exp_Defaults.Fs/1000))';
    ExpStruct.LEDoutput2(Ramp.rampstart_time*(Exp_Defaults.Fs/1000):Ramp.rampend_time*(Exp_Defaults.Fs/1000))=redOutput(Ramp.rampstart_time*(Exp_Defaults.Fs/1000):Ramp.rampend_time*(Exp_Defaults.Fs/1000))';

    % add ramp to blue LED to generate gamma oscillations
    ramp =make_ramp_output(Ramp.rampstart_time, Ramp.rampend_time, Ramp.rampstart_voltage, Ramp.rampend_voltage, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
    ExpStruct.LEDoutput = ExpStruct.LEDoutput+ramp; 
    ExpStruct.LEDoutput(ExpStruct.LEDoutput>5)=5; % ensure output stays below 5 Volts 
    ExpStruct.LEDoutput2(ExpStruct.LEDoutput2>5)=5;
%     plot(ExpStruct.timebase, ExpStruct.LEDoutput, ExpStruct.timebase, ExpStruct.LEDoutput2);%, ExpStruct.timebase, ramp, ExpStruct.timebase, ExpStruct.LEDoutput-ramp)

end
    

%% 
if get(h.oscillation_check, 'Value')
    [ExpStruct.LEDoutput,ExpStruct.LEDoutput2]= gammaCurrentInj(1,cell1.pulseamp, cell2.pulseamp, cell1.pulsefrequency,0, 0, 280,  ExpStruct.timebase, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
    ExpStruct.CCoutput1 = ExpStruct.CCoutput1'/Exp_Defaults.CCexternalcommandsensitivity;  ExpStruct.CCoutput1(end)=0;
%     ExpStruct.CCoutput2 = ExpStruct.CCoutput2/Exp_Defaults.CCexternalcommandsensitivity;  ExpStruct.CCoutput2(end)=0;

end
    

if get(h.ASAP_PsChR_check, 'Value')
    [ExpStruct.LEDoutput, ExpStruct.Lumencor_output, ExpStruct.CCoutput1] = updateASAP_PsChR_expt();
    ExpStruct.CCoutput1 = ExpStruct.CCoutput1/cell1.externalcommandsensitivity;
%     plot(h.analysis1_axes, ExpStruct.timebase, ExpStruct.CCoutput1, ExpStruct.timebase, ExpStruct.LEDoutput, ExpStruct.timebase, ExpStruct.Lumencor_output);
end

if get(h.BiPOLES_parameter_test_check, 'Value')
    updateBiPOLES_expt('Calibration');
end

if get(h.BiPOLES_calibration_check, 'Value')
%     updateBiPOLES_expt('Calibration');
%     [ExpStruct.LEDoutput, ExpStruct.LEDoutput2]=BiPOLES_EI_calibrate(LED.pulseamp,LED.pulseamp, 500);  
%     [ExpStruct.CCoutput1,ExpStruct.LEDoutput, ExpStruct.LEDoutput2]=BiPOLES_EI_inject(LED.pulseamp, LED.pulseamp*ExpStruct.EIratio, cell1.pulseamp, ExpStruct.numSteps );
%   [ExpStruct.LEDoutput, ExpStruct.LEDoutput2]=BiPOLES_inVivo_redBlue(LED.pulseamp,LED.pulseamp2 , ExpStruct.numSteps );
[ExpStruct.LEDoutput, ExpStruct.LEDoutput2]=BiPOLES_inVivo_redBlue_contrasts(LED.pulseamp, LED.pulseamp2, ExpStruct.numSteps,0 );
      
end

if get(h.BiPOLES_tuningCurveCheck, 'Value')

 [ExpStruct.CCoutput1, ExpStruct.LEDoutput, ExpStruct.LEDoutput2]=updateBiPOLES_tuningCurves([cell1.pulseamp, LED.pulseamp, LED.pulseamp*ExpStruct.EIratio], cell1.pulsenumber);
end

if get(h.BiPOLES_noise_test_check, 'Value')
%   updateBiPOLES_corrExpt()
[ExpStruct.LEDoutput,ExpStruct.LEDoutput2, ExpStruct.CCoutput1] = BiPOLES_EItest(LED.pulseamp, cell1.pulsenumber, 'uncorrelated noise');
%    plot(h.Whole_cell1_axes,ExpStruct.timebase,ExpStruct.cell1sweep, ExpStruct.timebase, ExpStruct.CCoutput1*98-30, ones(length(spi);
end


%% store Vclamp or Iclamp for each each trial
val_AMP = get(h.Cell1_type_popup, 'Value');
ExpStruct.clampSetting(ExpStruct.sweep_counter) = val_AMP;

%% Check if performing Lumencor dose response curve
val_LumencorDoseResponse = get(h.LumencorDoseResponseCheck, 'Value');
if val_LumencorDoseResponse == 1
    ExpStruct.LumencorIntensity(ExpStruct.sweep_counter) = LED.intensity;
  
    LED.intensity = (mod(ExpStruct.sweep_counter, 6))*100/6;
%     LED.intensity = log(LED.intensity/0.24)/0.7
    set_lumencor_intensity(LED.intensity, LED.color);
  
end




%% analyze second analog input for running (irrelevant if not an awake
% animals experiment)
running_trace = ExpStruct.cell2sweep;

% if Exp_Defaults.DIO_on == 1 % if V1 expt where stimulus is on 0.5-1.5 seconds
% %     speed = get_running_speed(running_trace, 0.2, .5); % change to these limits for high frequency stimulation
%     speed = get_running_speed(running_trace, 0.1, 1);
% else 
%     speed = get_running_speed(running_trace, .1, 1); % if barrel cortex experiment where stimuls is on 1-2.5 seconds
% end
% 
%     if speed > 200 % > 200 mV from ETach2, in current DIP switch settings is just above a slow walk
%         ExpStruct.running(ExpStruct.sweep_counter-1) = 1;
%     else
%         ExpStruct.running(ExpStruct.sweep_counter-1) = 0;
%     end

%% draw elapsed experiment time in whole cell1 axes
% ymax = get(h.Whole_cell1_axes, 'YLim'); ymax = ymax(2);
% xmax = get(h.Whole_cell1_axes, 'XLim'); xmax = xmax(2);
% if ymax > 1
%      text(0.9*xmax,0.8*ymax,current_sweep_time,'Parent',h.Whole_cell1_axes);
% else 
%      text(0.9*xmax,1.1*ymax,current_sweep_time,'Parent',h.Whole_cell1_axes);
% end

set(h.experiment_time, 'String', current_sweep_time);

%% perform tuning plot analysis and updatge tuning plot GUI if open
if ExpStruct.TuningPlot_on == 1
      TuningPlot_analysis;
end

%% perform Multituning plot analysis and update Multituning plot GUI if open
if ExpStruct.MultiVisStimPlot_on == 1
      MultiVisStimAnalysis(intDIO);
end

% for saving some data after each trial
% save(ExpStruct.SaveName, 'ExpStruct');

updateAOaxes; 
% put your own function here

% reward

% if using external trigger recall acquire()
if (Exp_Defaults.ExternalTrigger == 1) 
    acquire()
end

end
