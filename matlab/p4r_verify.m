function p4r_verify(root)
T=readtable(fullfile(root,'MANIFEST.csv'),'TextType','string','VariableNamingRule','preserve');
assert(all(ismember({'RelativePath','Bytes','SHA256'},T.Properties.VariableNames)),'Manifest schema');
assert(numel(unique(T.RelativePath))==height(T),'Duplicate manifest path');
for k=1:height(T)
    r=T.RelativePath(k);
    assert(~startsWith(r,'/') && ~contains(r,'..') && ~contains(r,':'),'Unsafe package path');
    f=fullfile(root,strrep(char(r),'/',filesep));
    assert(isfile(f),'Missing package file: %s',f);
    d=dir(f);assert(d.bytes==T.Bytes(k),'Byte-size mismatch: %s',f);
    assert(strcmpi(p4r_sha256(f),T.SHA256(k)),'Hash mismatch: %s',f);
end
fprintf('P4 RESEARCH PACKAGE SHA256 PASS: %d/%d\n',height(T),height(T));
end
