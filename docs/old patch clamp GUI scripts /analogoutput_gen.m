function [ AO0, AO1, AO2, AO3 ] = analogoutput_gen(~ )
% Generate four analog output vectors specified by type in setup_structs 
%call globals
global ExpStruct Exp_Defaults h s LED

% assign local values
testpulse=ExpStruct.testpulse; LEDoutput=ExpStruct.LEDoutput; piezooutput=ExpStruct.piezooutput; 
CCoutput1=ExpStruct.CCoutput1'; CCoutput2=ExpStruct.CCoutput2;


%% check if controlling command voltage for IV plot and add DC component to
% testpulse
if get(h.IVcurve_check, 'Value')
    testpulse = update_DCcommand(testpulse);
end


%% check if alternating Lumencor UV and Green for QAQ experiment
% val_QAQ_light = get(h.alt_QAQ_Light, 'Value');
% if (val_QAQ_light==1)
%   line2=makepulseoutputs(250, 1,999, -1 ,1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
%   line2=line2+1; 
% 
%     if mod((ExpStruct.sweep_counter),10)/10 < 0.5
%         
%          ExpStruct.Lumencor_output(:,1)=line2;
%          ExpStruct.Lumencor_output(:,5)=1;
%          ExpStruct.QAQcolor(ExpStruct.sweep_counter) = 1; % 1 for UV
%     else
%          ExpStruct.Lumencor_output(:,5)=line2;
%          ExpStruct.Lumencor_output(:,1)=1;
%          ExpStruct.QAQcolor(ExpStruct.sweep_counter) = 4; % 4 for Green
%     end
% end

%% check for voltage clamp, current clamp, or LFP recording for each analog
% input channel from GUI
value1 = get(h.Cell1_type_popup,'Value');
value2 = get(h.Cell2_type_popup,'Value');

    % set analog outputs to appropriate arrays based on values in Rig
    % Defaults set in setup_structs
    if (strcmp(Exp_Defaults.AO0,'wholecell')==1) % if whole cell1 on AO0
        if  value1==1 % if voltage clamp
           if get(h.ext_cmd_1_check,'value') ==1
            ExpStruct.testpulse = makepulseoutputs(50,1, 50, -0.2, 1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
           else
            ExpStruct.testpulse = makepulseoutputs(50,1, 50, 0, 1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
           end    
            AO0=testpulse;%CCoutput1;
        elseif get(h.ext_cmd_1_check,'Value')  % if currentclamp
            if get(h.oscillation_check,'Value')
               AO0=ExpStruct.CCoutput1'; 
            else
               ExpStruct.testpulse = makepulseoutputs(50,1, 250, -0.1, 1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
               AO0=testpulse+CCoutput1;
            end
        else
            AO0=CCoutput1;
        end
    end
    
    if strcmp(Exp_Defaults.AO0,'piezo') % 
        AO0=piezooutput; 
    end
    if strcmp(Exp_Defaults.AO0,'LEDoutput') % if whole cell1 on AO0
        AO0=LEDoutput;
    end
        
        
        if (strcmp(Exp_Defaults.AO0,'dynamicClamp')==1) 
        if get(h.PoissonInjCheck,'Value')==1 % if using poisson EPSG train for injection
%             [cV] = alphaConvolve(.3 ,0.001,0.015, Exp_Defaults.sweepduration-.5, 0.1, Exp_Defaults.Fs,200);
%             cV(end)=0;  
%             AO0(1:Exp_Defaults.Fs*Exp_Defaults.sweepduration)=0;
%             AO0(Exp_Defaults.Fs*.5+1:end)=cV'; AO0=AO0';
                
%              [cV] = alphaSingle(2.5,0.001,0.005, .5, 0.1, Exp_Defaults.Fs,0.4); cV(end)=0;
%             AO0(1:Exp_Defaults.Fs*.5)=cV';
%             plot(h.CCoutput_axes, ExpStruct.timebase, AO0);
            
             AO0 = ExpStruct.savedDynClampVector;
             plot(h.CCoutput_axes, ExpStruct.timebase, AO0);
        
        else 
            AO0 = testpulse;
        end
    end
        
    if (strcmp(Exp_Defaults.AO1,'wholecell')==1) % if whole cell1 on AO0
        if  value2==1 % if voltage clamp
            AO1=testpulse+CCoutput2;
        elseif get(h.ext_cmd_2_check,'Value')==1  % if currentclamp  
           if get(h.oscillation_check,'Value')
            AO1=ExpStruct.CCoutput2'; 
           else
            ExpStruct.testpulse = makepulseoutputs(50,1, 250, -0.1, 1, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
            AO1=testpulse+CCoutput1;
           end
        elseif get(h.PoissonInjCheck,'Value')==1 % if using poisson EPSG train for injection
            [cV] = alphaConvolve(.3 ,0.001,0.025, Exp_Defaults.sweepduration, 0.1, Exp_Defaults.Fs,800);
            cV(end)=0;    
            AO1=cV';
        elseif get(h.SingleEPSG_check,'Value')==1 % if using single EPSG for dynamic clamp
            [cV] = alphaSingle(.5,0.001,0.005, Exp_Defaults.sweepduration, 0.1, Exp_Defaults.Fs,0.2); cV(end)=0;
            AO1=cV';
            plot(h.CCoutput_axes, ExpStruct.timebase, cV);
        
            
        else
         AO1=CCoutput2;
        end
    end
    
    AO1=CCoutput1';
    
    if (strcmp(Exp_Defaults.AO1,'LEDoutput')==1)
        AO1=ExpStruct.LEDoutput;
    end
    
     if (strcmp(Exp_Defaults.AO1,'LEDoutput2')==1)
        AO1=ExpStruct.LEDoutput2;
    end
    
    if  (strcmp(Exp_Defaults.AO1,'galvox')==1)
         AO1=ExpStruct.galvoxOutput;
    end
        
     if (strcmp(Exp_Defaults.AO1,'shutterTrigger')==1)
        AO1=ExpStruct.shutterTriggerOutput;
    end
    
    if (strcmp(Exp_Defaults.AO2,'LEDoutput')==1)
        if get(h.Highpass_check, 'Value'); % If loose patch expt BiPOLES
            redpulse=makepulseoutputs(100, 1, 800, 1,LED.pulseamp, Exp_Defaults.Fs, Exp_Defaults.sweepduration);
            AO2=ExpStruct.LEDoutput+redpulse; updateAOaxes;
        else
            AO2=ExpStruct.LEDoutput; 
        end
    end
    
    if (strcmp(Exp_Defaults.AO2,'LEDoutput2')==1)
        AO2=ExpStruct.LEDoutput2;
    end
    if (strcmp(Exp_Defaults.AO3,'LEDoutput')==1)
        AO3=ExpStruct.LEDoutput;
    end
    
    if (strcmp(Exp_Defaults.AO3,'LEDoutput2')==1)
        AO3=ExpStruct.LEDoutput2;
    end
    
    if (strcmp(Exp_Defaults.AO2,'motorpulses')==1)
        AO2=ExpStruct.motorpulses;
    end
    
    if (strcmp(Exp_Defaults.AO3,'wholecell')==1)
       AO3=testpulse;
    end
    
    if (strcmp(Exp_Defaults.AO3,'motordir')==1)
        AO3=ExpStruct.motordir;
    end
    
    if  (strcmp(Exp_Defaults.AO3,'galvoy')==1)
         AO3=ExpStruct.galvoyOutput;

    % force all output vectors to be column vecotrs
    
    end 
    AO0 = AO0(:);
    AO1 = AO1(:);
    AO2 = AO2(:);
    AO3 = AO3(:);
   
% end