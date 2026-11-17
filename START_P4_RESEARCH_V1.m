function outDir = START_P4_RESEARCH_V1(mode,pythonExe)
% MATLAB R2023a entry. Reference runs use the supplied Python core.
% No original V173 functions are placed on the MATLAB path or executed.
if nargin<1, mode='review'; end
if nargin<2, pythonExe=''; end
root=fileparts(mfilename('fullpath'));
addpath(fullfile(root,'matlab'),'-begin');
p4r_verify(root);
p4r_selftest();
outDir=fullfile(root,'results','REFERENCE_20261117');
switch lower(char(mode))
    case 'review'
        assert(isfile(fullfile(outDir,'RUN_SUMMARY.json')),'Included reference output missing.');
        disp(jsondecode(fileread(fullfile(outDir,'RUN_SUMMARY.json'))));
        fprintf('Review: %s\n',fullfile(outDir,'index.html'));
        fprintf('These are reference/component results, not the formal SF24 experiment.\n');
    case 'reproduce'
        if isempty(pythonExe)
            pe=pyenv;
            pythonExe=char(pe.Executable);
            if isempty(pythonExe), pythonExe='python'; end
        end
        assert(~contains(pythonExe,'"'),'Invalid executable path.');
        outDir=fullfile(root,'runs',['REFERENCE_' datestr(now,'yyyymmdd_HHMMSS_FFF')]);
        assert(~isfolder(outDir),'Output already exists.');
        cmd=sprintf('"%s" "%s" --out "%s" --mc 1000', ...
            pythonExe,fullfile(root,'python','run.py'),outDir);
        [status,msg]=system(cmd,'-echo');
        assert(status==0,'Reference runner failed: %s',msg);
        disp(jsondecode(fileread(fullfile(outDir,'RUN_SUMMARY.json'))));
    case 'preserve'
        ws='C:\Users\Xiao\Desktop\Four Paper\CODE2\P4_V173_CODE2_WORKSPACE_20261111';
        parent=fullfile(ws,'09_RUN_OUTPUTS','P4RH_P5_P3_V101', ...
            'RUN_20261117_005654_211_P5P3','P5P3_FINAL_EVIDENCE_WITH_ACCEPTANCE.zip');
        assert(isfile(parent),'Frozen P5P3 ZIP missing at the exact declared path.');
        outDir=fullfile(root,'runs',['PRESERVED_' datestr(now,'yyyymmdd_HHMMSS_FFF')]);
        p4r_import_p5p3(parent,outDir);
    otherwise
        error('Mode must be review, reproduce or preserve.');
end
fprintf('Production Admission = CLOSED. No 135-case recomputation.\n');
end
