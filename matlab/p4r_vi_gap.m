function G=p4r_vi_gap(flow,cost,groups)
flow=flow(:);cost=cost(:);assert(isequal(size(flow),size(cost)));
assert(all(isfinite(flow)&flow>=0)&&~any(isnan(cost)));
bad=sum(flow(~isfinite(cost)));
G=struct('relativeGap',Inf,'absoluteGap',Inf,'worstExcess',Inf,'infeasibleMass',bad);
if bad>0,return;end
numer=0;denom=0;worst=0;
for k=1:numel(groups)
    ix=groups{k};ix=ix(isfinite(cost(ix)));
    if isempty(ix),continue;end
    excess=cost(ix)-min(cost(ix));
    numer=numer+sum(flow(ix).*excess);denom=denom+sum(flow(ix).*abs(cost(ix)));
    used=flow(ix)>0;if any(used),worst=max(worst,max(excess(used)));end
end
G.relativeGap=numer/max(denom,1e-15);G.absoluteGap=numer;G.worstExcess=worst;
end
