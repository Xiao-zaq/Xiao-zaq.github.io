function p4r_selftest()
n=0;
for c=[.25,.5,1,2,4]
    [lambda,mu]=p4r_rates(.97,60,c);assert(abs(mu/(lambda+mu)-.97)<1e-14);n=n+1;
end
[b,r,e]=p4r_wcl(18,36,2,60,4,60,.9,12);assert(abs(e-3.6)<1e-12&&abs(b-19.6)<1e-12&&abs(r-32.4)<1e-12);n=n+1;
[bb,rr,ee]=p4r_wcl(b,r,0,60,0,60,.9,12);assert(bb==b&&rr==r&&ee==0);n=n+1;
failed=false;try,p4r_wcl(12,0,1,0,0,60,.9,12);catch,failed=true;end;assert(failed);n=n+1;
old=[10;20;5];[next,f]=p4r_ctm_chain(old,[4;4;4],[30;30;30],[1;1;1],[.5;.5;.5],1,3,2);
assert(abs(sum(next)-sum(old)-f(1)+f(end))<1e-12);n=n+1;
x=p4r_simplex([3;-2;5],4);assert(norm(x-[1;0;3],Inf)<1e-12);n=n+1;
R=p4r_solve_vi(@(x)[2+2*x(1);5+x(2)],{[1,2]},10,[10;0],2000,1e-8,.4);
assert(R.converged&&norm(R.flow-[13/3;17/3],Inf)<2e-7);n=n+1;
G=p4r_vi_gap([1;3e-9],[1;Inf],{[1,2]});assert(isinf(G.relativeGap)&&G.infeasibleMass==3e-9);n=n+1;
Y=p4r_pool_delay([1,0;0,1;1,0;0,1],2);assert(isequal(Y,[0,0;0,0;1,0;0,1]));n=n+1;
fprintf('MATLAB local analytic/component checks: %d/%d PASS.\n',n,n);
fprintf('This message is issued only after MATLAB actually runs these checks.\n');
end
