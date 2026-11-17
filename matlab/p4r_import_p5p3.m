function p4r_import_p5p3(zipFile,outDir)
% Validate and preserve the exact previous P5P3 archive; never resimulate it.
assert(isfile(zipFile)&&~isfolder(outDir),'Input missing or output already exists.');
zf=java.util.zip.ZipFile(zipFile);closeZip=onCleanup(@()zf.close()); %#ok<NASGU>
entries=zf.entries();names=strings(0,1);
while entries.hasMoreElements()
    en=entries.nextElement();s=string(en.getName());
    assert(~contains(s,'/')&&~contains(s,'\')&&~contains(s,'..')&&~en.isDirectory(),'Expected flat evidence archive.');
    names(end+1,1)=s; %#ok<AGROW>
end
assert(numel(names)==13&&numel(unique(names))==13,'Evidence member count or duplicates.');
stage=tempname;mkdir(stage);clean=onCleanup(@()rmdir(stage,'s')); %#ok<NASGU>
unzip(zipFile,stage);
M=readtable(fullfile(stage,'P5P3_EVIDENCE_MANIFEST.csv'),'TextType','string','VariableNamingRule','preserve');
assert(height(M)==12&&isequal(sort(names),sort([M.RelativePath;"P5P3_EVIDENCE_MANIFEST.csv"])),'Manifest membership.');
for k=1:height(M)
    f=fullfile(stage,M.RelativePath(k));d=dir(f);
    assert(d.bytes==M.Bytes(k)&&strcmpi(p4r_sha256(f),M.SHA256(k)),'Evidence bytes/hash failed.');
end
anchorNames={ ...
 'P5P3_EXACT_SAVED_FLOW_WITNESS.mat', ...
 'P5P3_DEPARTURE_COHORT_MAPPING.csv', ...
 'P5P3_DEPARTURE_TIME_CLASS_TOTAL.csv'};
anchorHashes={ ...
 '7367524514b11a4e8424ee2063b47f69090f8bce211a55d9ea1992868d012ce4', ...
 'b49266154f57adb94164ff956637b7403973f38cd4bd53846e1b4d09457c0a1f', ...
 '8729aba734022a8d60b1013e504d656433e6f45cd9e014984538f1a8641292fa'};
for k=1:numel(anchorNames)
    assert(strcmpi(p4r_sha256(fullfile(stage,anchorNames{k})),anchorHashes{k}),'Frozen external anchor mismatch.');
end
S=load(fullfile(stage,anchorNames{1}),'Fstar','Finitial','PreparedFlow');F=S.Fstar;
assert(isequal(size(F),[107,2,241])&&all(isfinite(F(:)))&&all(F(:)>=0),'F shape/values.');
assert(abs(sum(F(:))-3620)<1e-8&&nnz(F)==7538,'Demand or positive count.');
C=readtable(fullfile(stage,anchorNames{2}),'VariableNamingRule','preserve');
ix=sub2ind(size(F),C.PathID,C.SOCClassID,C.DepartureTimeIndex);
assert(numel(unique(ix))==height(C)&&height(C)==7538,'Duplicate/missing cohort.');
R=zeros(size(F));R(ix)=C.MassVeh;
assert(isequal(R>0,F>0)&&all(abs(R(:)-F(:))<=1e-15+1e-12*abs(F(:))),'Exact tensor/CSV mismatch.');
assert(abs(sum(F(:,1,:),'all')-2534)<1e-8&&abs(sum(F(:,2,:),'all')-1086)<1e-8,'Class mass.');
A=readtable(fullfile(stage,'P5P3_INDEPENDENT_SAVED_ACCEPTANCE.csv'),'VariableNamingRule','preserve');
assert(height(A)==17&&all(A.Pass==1),'Original acceptance not 17/17.');
L=readtable(fullfile(stage,'P5P3_LINK_CAPACITY_AND_PATH_INCIDENCE.csv'),'TextType','string','VariableNamingRule','preserve');
isTraffic=L.Kind=="ROAD"|L.Kind=="WCL";
assert(height(L)==104&&sum(isTraffic)==96,'Link inventory.');
assert(max(abs(L.DeparturePathIncidenceVeh(isTraffic)-L.SavedIntegratedRoadVolumeVeh(isTraffic)))<1e-8,'Integrated link volume.');
mkdir(outDir);
for k=1:numel(names),copyfile(fullfile(stage,names(k)),fullfile(outDir,names(k)));end
copyfile(zipFile,fullfile(outDir,'ORIGINAL_P5P3.zip'));
assert(strcmp(p4r_sha256(zipFile),p4r_sha256(fullfile(outDir,'ORIGINAL_P5P3.zip'))));
f=fopen(fullfile(outDir,'PRESERVATION_STATUS.txt'),'w');
fprintf(f,'P5P3 mapping technical evidence preserved byte-for-byte.\nProduction Admission CLOSED.\nNo formal DNL/DUE certification.\n');fclose(f);
p4r_plot_saved(stage,outDir);
fprintf('P5P3 hashes 12/12; frozen anchors 3/3; saved mass %.15g veh.\n',sum(F(:)));
end
