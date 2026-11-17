function applied=p4r_pool_delay(planned,delay)
assert(isscalar(delay)&&delay>=0&&delay==floor(delay)&&all(isfinite(planned(:)))&&all(planned(:)>=0));
applied=zeros(size(planned));
if delay==0,applied=planned;elseif delay<size(planned,1),applied(delay+1:end,:)=planned(1:end-delay,:);end
end
