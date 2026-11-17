function h=p4r_sha256(file)
fid=fopen(file,'rb');assert(fid>=0,'Cannot read %s',file);
guard=onCleanup(@()fclose(fid)); %#ok<NASGU>
md=java.security.MessageDigest.getInstance('SHA-256');
while true
    b=fread(fid,1048576,'*uint8');
    if isempty(b),break;end
    md.update(b);
end
h=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
end
