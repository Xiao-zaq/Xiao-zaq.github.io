function outDir = p5p4_formal_source_bridge(ws)
% Fourth Paper P5-P4 V1. Frozen formal SF24 source bridge only.
% MATLAB R2023a. No historical reruns, no DNL/DUE/market execution.
if nargin<1||isempty(ws)
 ws='C:\Users\Xiao\Desktop\Four Paper\CODE2\P4_V173_CODE2_WORKSPACE_20261111';
end
assert(isfolder(ws),'P5P4:Workspace','Workspace missing.');
formal=fullfile(ws,'01_ACTIVE_CODE_PACKAGES','P4RH_P5_P1_V1',...
 'FORMAL_INPUTS','Data','Inherited');
networkFile=fullfile(formal,'SF24_R654_FormalNetwork_V160.mat');
pathsFile=fullfile(formal,'P4_SF24_R654_Paths_107_V160.mat');
zipFile=fullfile(ws,'09_RUN_OUTPUTS','P4RH_P5_P3_V101',...
 'RUN_20261117_005654_211_P5P3','P5P3_FINAL_EVIDENCE_WITH_ACCEPTANCE.zip');
assert(strcmpi(sha(networkFile),...
 '196f95bd7f017ae1e88848d96d40129ff7880de8662e8ae81943db66fb8f3ac9'),...
 'P5P4:NetworkSHA','Frozen network SHA mismatch.');
assert(strcmpi(sha(pathsFile),...
 '50a24b7419269a432db6346b1717e58c999630410b00c789bcffe16dfb0b6936'),...
 'P5P4:PathsSHA','Frozen paths SHA mismatch.');
assert(strcmpi(sha(zipFile),...
 'f0fb7fa91cfdeb73931982450c6f4bb62cfb406d86756dd6fbed8e1a9b61a426'),...
 'P5P4:EvidenceSHA','Frozen P5P3 evidence ZIP SHA mismatch.');
stage=tempname;mkdir(stage);cleanup=onCleanup(@()removeStage(stage)); %#ok<NASGU>
unzip(zipFile,stage);
L=readtable(fullfile(stage,'P5P3_EVIDENCE_MANIFEST.csv'),...
 'TextType','string','VariableNamingRule','preserve');
assert(isequal(L.Properties.VariableNames,...
 {'RelativePath','Bytes','SHA256'})&&height(L)==12,...
 'P5P4:ManifestSchema','Evidence manifest schema invalid.');
for i=1:height(L)
 n=char(L.RelativePath(i));
 assert(~contains(n,'..')&&~contains(n,'/')&&...
 ~contains(n,'\')&&~contains(n,':'),'P5P4:ZipPath','Unsafe evidence member.');
 f=fullfile(stage,n);d=dir(f);
 assert(isfile(f)&&d.bytes==L.Bytes(i)&&...
 strcmpi(sha(f),L.SHA256(i)),...
 'P5P4:MemberSHA','Saved evidence member hash mismatch.');
end
D=load(fullfile(stage,'P5P3_EXACT_SAVED_FLOW_WITNESS.mat'),...
 'Fstar','Finitial','PreparedFlow');F=D.Fstar;
assert(isequal(size(F),[107,2,241])&&all(isfinite(F(:)))&&...
 all(F(:)>=0)&&abs(sum(F(:))-3620)<1e-8&&nnz(F)==7538,...
 'P5P4:SavedF','Saved F* domain/count incorrect.');
C=readtable(fullfile(stage,'P5P3_DEPARTURE_COHORT_MAPPING.csv'),...
 'VariableNamingRule','preserve');
needed={'DepartureTimeIndex','PathID','SOCClassID','ODIndex',...
 'StationID','MassVeh'};
assert(height(C)==7538&&all(ismember(needed,C.Properties.VariableNames)),...
 'P5P4:CSVSchema','Saved departure-cohort schema mismatch.');
index=sub2ind(size(F),C.PathID,C.SOCClassID,C.DepartureTimeIndex);
B=zeros(size(F));B(index)=C.MassVeh;
assert(numel(unique(index))==height(C)&&all(C.MassVeh>0)&&...
 isequal(B>0,F>0)&&all(abs(B(:)-F(:))<=1e-12.*max(1,abs(F(:)))),...
 'P5P4:CSVvsMAT','CSV does not reconstruct all positive F*.');
V=load(networkFile,'networkState');N=V.networkState;
V=load(pathsFile,'paths');P=V.paths;
kind=string(N.kind(:));tail=double(N.tail(:));head=double(N.head(:));
assert(numel(kind)==104&&numel(P)==107&&...
 sum(kind=="ROAD")==76&&sum(kind=="WCL")==20&&...
 sum(kind=="FCS")==4&&sum(kind=="EXIT")==4,...
 'P5P4:TopologyDomain','Formal topology mismatch.');
assert(isequal(double([P.id]'),(1:107)'),...
 'P5P4:PathOrder','Fstar indices do not match path identities.');
odOfPath=double([P.odIndex]);stationOfPath=double([P.station]);
assert(all(C.ODIndex==odOfPath(C.PathID)')&&...
 all(C.StationID==stationOfPath(C.PathID)'),...
 'P5P4:PathMetadata','Saved cohort metadata inconsistent.');
count=sum(arrayfun(@(p)numel(p.linkSeq),P));
raw=zeros(count,4);nrow=0;
for i=1:numel(P)
 r=double(P(i).linkSeq(:));odi=double(P(i).odIndex);
 s=double(P(i).station);
 assert(~isempty(r)&&all(r>=1&r<=104)&&...
 all(head(r(1:end-1))==tail(r(2:end))),...
 'P5P4:Connected','Path %d has invalid link chain.',i);
 assert(tail(r(1))==N.od(odi,1)&&head(r(end))==N.od(odi,2)&&...
 sum(kind(r)=="FCS")==1&&sum(kind(r)=="EXIT")==1&&...
 sum(r==N.fcsLinks(s))==1,...
 'P5P4:ServicePath','Path %d fails formal OD/FCS test.',i);
 for j=1:numel(r)
   nrow=nrow+1;raw(nrow,:)=[i j r(j) odi];
 end
end
PT=table(raw(:,1),raw(:,2),raw(:,3),raw(:,4),...
 'VariableNames',{'PathID','Position','LinkID','ODIndex'});
LinkID=(1:104)';Kind=kind;
DeclaredCapacityVehPerMin=double(N.capacity(:));
traffic=Kind=="ROAD"|Kind=="WCL";
assert(all(isfinite(DeclaredCapacityVehPerMin(traffic))&...
 DeclaredCapacityVehPerMin(traffic)>0),'P5P4:CapacitySource');
HardDischargeCertified=false(104,1);
FiniteStorageCertified=false(104,1);
DistanceKmCertified=false(104,1);
CapacitySemantics=repmat("SOURCE_DECLARED_NOT_CERTIFIED_CTMCAPACITY",104,1);
LT=table(LinkID,Kind,DeclaredCapacityVehPerMin,CapacitySemantics,...
 HardDischargeCertified,FiniteStorageCertified,DistanceKmCertified);
base=fullfile(ws,'09_RUN_OUTPUTS','P4RH_P5_P4_SOURCE_BRIDGE_V1');
if ~isfolder(base),mkdir(base);end
outDir=fullfile(base,['RUN_' datestr(now,'yyyymmdd_HHMMSS_FFF') '_P5P4']);
assert(~isfolder(outDir),'P5P4:Overwrite','Output exists.');
mkdir(outDir);
writetable(C,fullfile(outDir,'P5P4_DEPARTURE_COHORT_INPUT.csv'));
writetable(PT,fullfile(outDir,'P5P4_PATH_LINK_SEQUENCE.csv'));
writetable(LT,fullfile(outDir,'P5P4_LINK_PHYSICAL_PROVENANCE.csv'));
save(fullfile(outDir,'P5P4_EXACT_INPUT_WITNESS.mat'),'F','P','N','-v7.3');
Metric=["MappedVeh";"PositiveDepartureCells";"FormalPaths";...
 "FormalLinks";"SmallPositiveUnder1eMinus8";"OriginalEvidenceMembers"];
Value=[sum(F(:));height(C);numel(P);numel(kind);...
 sum(C.MassVeh<1e-8);height(L)];
writetable(table(Metric,Value),fullfile(outDir,'P5P4_SUMMARY.csv'));
Gate=["SAVED_SOURCE_SHA";"FSTAR_DEPARTURE_MASS";...
 "ORDERED_PATH_TOPOLOGY";"HARD_CTMCAPACITY";"FINITE_STORAGE";...
 "PHYSICAL_KM_DISTANCE";"FORMAL_FIXED_FLOW_DNL";...
 "PRE_EVENT_DUE";"ROLLING_RESIDUAL_VI"];
Status=["PASS";"PASS";"PASS";repmat("NOT_GRANTED",6,1)];
writetable(table(Gate,Status),fullfile(outDir,'P5P4_SCIENCE_GATES.csv'));
M=dir(fullfile(outDir,'*'));M=M(~[M.isdir]);
RelativePath=strings(numel(M),1);Bytes=zeros(numel(M),1);
SHA256=strings(numel(M),1);
for j=1:numel(M)
 RelativePath(j)=string(M(j).name);Bytes(j)=M(j).bytes;
 SHA256(j)=sha(fullfile(outDir,M(j).name));
end
writetable(table(RelativePath,Bytes,SHA256),...
 fullfile(outDir,'P5P4_OUTPUT_HASH_MANIFEST.csv'));
zip(fullfile(outDir,'P5P4_FINAL_SOURCE_BRIDGE_EVIDENCE.zip'),...
 cellstr(RelativePath),outDir);
fprintf('P5P4 F* INPUT MAPPING PASS: 3620 veh; 107 paths; 7538 departure cells.\n');
fprintf('Parent evidence 12/12 SHA verified. No DNL/DUE/135 cases executed.\n');
fprintf('Saved result: %s\nPRODUCTION_ADMISSION = CLOSED.\n',outDir);
end
function s=sha(file)
assert(isfile(file),'P5P4:MissingInput','Required frozen file missing.');
md=java.security.MessageDigest.getInstance('SHA-256');
f=fopen(file,'rb');assert(f>0);c=onCleanup(@()fclose(f)); %#ok<NASGU>
while true
 b=fread(f,1024*1024,'*uint8');if isempty(b),break;end
 md.update(typecast(b,'int8'));
end
s=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
function removeStage(p)
if isfolder(p),rmdir(p,'s');end
end