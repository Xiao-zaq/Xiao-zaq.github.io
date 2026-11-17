function R=p4r_solve_vi(oracle,groups,demand,initial,maxIter,tol,step)
% Frozen-state finite-alternative extragradient; nonconvergence is exposed.
% oracle must evaluate all feasible alternatives without committing state.
if nargin<5,maxIter=2000;end
if nargin<6,tol=1e-8;end
if nargin<7,step=.1;end
x=initial(:);flat=[groups{:}];
assert(numel(flat)==numel(x)&&isequal(sort(flat(:)),(1:numel(x))'));
assert(numel(groups)==numel(demand));x=project(x);c=oracle(x);c=c(:);
assert(all(isfinite(c))&&isequal(size(c),size(x)),'Finite feasible oracle required');
history=zeros(maxIter,4);converged=false;
for k=1:maxIter
    alpha=step;ok=false;
    for trial=1:35
        y=project(x-alpha*c);cy=oracle(y);cy=cy(:);
        assert(isequal(size(cy),size(x))&&all(isfinite(cy)),'Oracle feasibility changed');
        if alpha*norm(cy-c)<=.7*norm(y-x)+1e-15,ok=true;break;end
        alpha=alpha/2;
    end
    assert(ok,'Extragradient line search failed');
    next=project(x-alpha*cy);delta=norm(next-x,1)/max(1,sum(demand));x=next;
    c=oracle(x);c=c(:);assert(all(isfinite(c))&&isequal(size(c),size(x)));
    gap=p4r_vi_gap(x,c,groups);history(k,:)=[k,gap.relativeGap,delta,alpha];
    if gap.relativeGap<=tol&&delta<=tol,converged=true;break;end
end
R=struct('flow',x,'cost',c,'gap',gap,'history',history(1:k,:),'converged',converged);
    function out=project(v)
        out=zeros(size(v));
        for j=1:numel(groups),ix=groups{j};out(ix)=p4r_simplex(v(ix),demand(j));end
    end
end
