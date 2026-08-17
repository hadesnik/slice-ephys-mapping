function close_req_fcn(src,evnt)
% User-defined close request function 
% to display a question dialog box 

global ExpStruct cell1 cell2 LED Ramp Exp_Defaults h sweeps sweeps_DI

selection = questdlg('Save and Close?',...
      'Close Request Function',...
      'Yes','No','Yes'); 
   switch selection, 
      case 'Yes',
         % need to add lines to confirm if overwrities previous file
          delete(gcf)
         save(ExpStruct.SaveName);
        
      case 'No'
      return 
   end
end