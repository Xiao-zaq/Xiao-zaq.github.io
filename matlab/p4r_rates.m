function [lambda,mu]=p4r_rates(a,mttr,scale)
assert(isscalar(a)&&a>0&&a<1&&isscalar(mttr)&&mttr>0&&isscalar(scale)&&scale>0);
mu=scale/mttr;lambda=mu*(1-a)/a;
end
