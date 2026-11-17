function x=p4r_simplex(v,demand)
assert(all(isfinite(v(:)))&&isfinite(demand)&&demand>=0&&~isempty(v));
if demand==0,x=zeros(size(v));return;end
u=sort(v(:),'descend');s=cumsum(u)-demand;
rho=find(u-s./(1:numel(u))'>0,1,'last');
x=max(v-s(rho)/rho,0);
end
