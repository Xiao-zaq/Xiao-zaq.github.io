function [battery,remaining,energy]=p4r_wcl(battery,remaining,traction,power,minutes,capacity,efficiency,bmin)
% Uniform simultaneous movement/charging. Downstream queue minutes = 0.
assert(all(isfinite([battery remaining traction power minutes capacity efficiency bmin])));
assert(battery>=0&&battery<=capacity&&remaining>=0&&traction>=0&&power>=0&&minutes>=0);
assert(efficiency>0&&efficiency<=1&&capacity>0);
old=battery;
energy=min([remaining,power*efficiency*minutes/60,max(0,capacity-battery+traction)]);
battery=battery-traction+energy;remaining=remaining-energy;
assert(min(old,battery)>=bmin-1e-10,'Hard SOC infeasibility.');
end
