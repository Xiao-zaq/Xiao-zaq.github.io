function bundle=EXPORT_P4_LOCAL_INPUTS(ws)
% Export exact SMALL formal assets from Code2 without running production.
% This does not invent a schema for an uninspected MAT or copy 135 cases.
root=fileparts(mfilename('fullpath'));addpath(fullfile(root,'matlab'),'-begin');
if nargin<1,ws='C:\Users\Xiao\Desktop\Four Paper\CODE2\P4_V173_CODE2_WORKSPACE_20261111';end
files={ ...
 fullfile(ws,'01_ACTIVE_CODE_PACKAGES','P4RH_P5_P1_V1','FORMAL_INPUTS','Data','Inherited','SF24_R654_FormalNetwork_V160.mat'), ...
 fullfile(ws,'01_ACTIVE_CODE_PACKAGES','P4RH_P5_P1_V1','FORMAL_INPUTS','Data','Inherited','P4_SF24_R654_Paths_107_V160.mat'), ...
 fullfile(ws,'09_RUN_OUTPUTS','P4RH_P5_P3_V101','RUN_20261117_005654_211_P5P3','P5P3_FINAL_EVIDENCE_WITH_ACCEPTANCE.zip')};
hashes={ ...
 '196f95bd7f017ae1e88848d96d40129ff7880de8662e8ae81943db66fb8f3ac9', ...
 '50a24b7419269a432db6346b1717e58c999630410b00c789bcffe16dfb0b6936'};
for k=1:numel(files),assert(isfile(files{k}),'Missing exact source: %s',files{k});end
for k=1:2,assert(strcmpi(p4r_sha256(files{k}),hashes{k}),'Frozen formal asset hash mismatch.');end
out=fullfile(root,'runs',['LOCAL_INPUTS_' datestr(now,'yyyymmdd_HHMMSS_FFF')]);
mkdir(out);M=cell(numel(files),3);
for k=1:numel(files)
    [~,n,e]=fileparts(files{k});copyfile(files{k},fullfile(out,[n e]));d=dir(files{k});
    M(k,:)={[n e],d.bytes,p4r_sha256(files{k})};
end
writetable(cell2table(M,'VariableNames',{'File','Bytes','SHA256'}),fullfile(out,'INPUT_MANIFEST.csv'));
bundle=[out '.zip'];zip(bundle,{'*'},out);
fprintf('Small formal input bundle: %s\n',bundle);
end
