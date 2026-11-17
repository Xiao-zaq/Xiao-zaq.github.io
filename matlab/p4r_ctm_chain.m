function [next,flux]=p4r_ctm_chain(n,q,jam,v,w,dt,upstream,downstream)
% Serial Godunov chain only; explicit CTM parameters, no BPR conversion.
n=n(:);q=q(:);jam=jam(:);v=v(:);w=w(:);
assert(isequal(size(n),size(q),size(jam),size(v),size(w))&&~isempty(n));
assert(all(isfinite([n;q;jam;v;w;dt;upstream;downstream]))&&dt>0);
assert(all(n>=0&n<=jam&q>=0&v>=0&v<=1&w>=0&w<=1)&&upstream>=0&&downstream>=0,'CTM/CFL inputs');
S=min(v.*n,q*dt);R=min(w.*(jam-n),q*dt);
flux=[min(upstream*dt,R(1));min(S(1:end-1),R(2:end));min(S(end),downstream*dt)];
next=n+flux(1:end-1)-flux(2:end);
end
