function p5p4_independent_accept(runDir)
% Independent saved-only P5-P4 output audit. No DNL/DUE calls.
assert(isfolder(runDir),'P5P4:RunMissing');
m=readtable(fullfile(runDir,'P5P4_OUTPUT_HASH_MANIFEST.csv'),...
 'TextType','string','VariableNamingRule','preserve');
assert(height(m)==6&&isequal(m.Properties.VariableNames,...
 {'RelativePath','Bytes','SHA256'}),'P5P4:Manifest');
for j=1:height(m)
 f=fullfile(runDir,char(m.RelativePath(j)));d=dir(f);
 assert(isfile(f)&&d.bytes==m.Bytes(j)&&strcmpi(sha(f),m.SHA256(j)),...
 'P5P4:Hash','Output hash mismatch');
end
C=readtable(fullfile(runDir,'P5P4_DEPARTURE_COHORT_INPUT.csv'));
P=readtable(fullfile(runDir,'P5P4_PATH_LINK_SEQUENCE.csv'));
L=readtable(fullfile(runDir,'P5P4_LINK_PHYSICAL_PROVENANCE.csv'));
S=load(fullfile(runDir,'P5P4_EXACT_INPUT_WITNESS.mat'),'F','P','N');F=S.F;
ix=sub2ind(size(F),C.PathID,C.SOCClassID,C.DepartureTimeIndex);
X=zeros(size(F));X(ix)=C.MassVeh;
assert(isequal(size(F),[107 2 241])&&nnz(F)==7538&&height(C)==7538);
assert(numel(unique(ix))==height(C)&&all(C.MassVeh>0)&&...
 max(abs(X(:)-F(:)))<1e-12&&abs(sum(F(:))-3620)<1e-8);
assert(height(L)==104&&sum(L.HardDischargeCertified)==0&&...
 sum(L.FiniteStorageCertified)==0&&sum(L.DistanceKmCertified)==0,...
 'P5P4:FalseCertification');
assert(height(P)==sum(arrayfun(@(p)numel(p.linkSeq),S.P)));
G=readtable(fullfile(runDir,'P5P4_SCIENCE_GATES.csv'),'TextType','string');
assert(height(G)==9&&sum(G.Status=="PASS")==3&&...
 sum(G.Status=="NOT_GRANTED")==6);
fprintf('P5P4 independent saved-only audit PASS: %d/6 output hashes.
',height(m));
fprintf('Formal SF24 DNL/DUE NOT_GRANTED; Production Admission CLOSED.
');
end
function s=sha(f)
md=java.security.MessageDigest.getInstance('SHA-256');
fid=fopen(f,'rb');assert(fid>0);cl=onCleanup(@()fclose(fid)); %#ok<NASGU>
while true
 b=fread(fid,1024*1024,'*uint8');if isempty(b),break;end
 md.update(typecast(b,'int8'));
end
s=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end