"""P4 research primitives. Minutes, veh, kW, kWh; no historical data writes.

These components are executable development/reference models. They are not a
certification of the missing V173 production DNL, rolling DUE or repair game.
"""
from __future__ import annotations
from dataclasses import dataclass, replace
from collections import deque
import math
import numpy as np


def reliability_rates(availability, mttr_min, scale=1.):
    if not np.isfinite([availability,mttr_min,scale]).all() or not (0 < availability < 1 and mttr_min > 0 and scale > 0):
        raise ValueError("Require 0<a<1, MTTR>0 and scale>0")
    mu = scale / mttr_min
    return mu * (1 - availability) / availability, mu


class PortClock:
    """Exact integrated-hazard clock, with persistent per-port thresholds.

    A control update changes the hazard RATE, never resets remaining hazard.
    Individual random streams give matched event-order CRN across policies.
    shock() is called only at the physical event time; it cannot be observed
    by a decision function before that time. Natural failures use the same
    failure stream after forced failures, which only draw repair thresholds.
    """
    def __init__(self, count, seed=1, initial_up=None):
        if int(count) != count or count < 1:
            raise ValueError("Equivalent reliability component count is integral")
        self.n = int(count)
        self.up = np.ones(self.n, dtype=bool) if initial_up is None else np.array(initial_up, bool)
        if self.up.shape != (self.n,):
            raise ValueError("initial_up shape")
        ss = np.random.SeedSequence(seed).spawn(2*self.n)
        self.failure_rng = [np.random.default_rng(s) for s in ss[:self.n]]
        self.repair_rng = [np.random.default_rng(s) for s in ss[self.n:]]
        self.remaining = np.array([self._draw(j) for j in range(self.n)])
        self.time = 0.
        self.events = []

    def _draw(self, j):
        rng = self.failure_rng[j] if self.up[j] else self.repair_rng[j]
        return max(float(rng.exponential()), np.finfo(float).tiny)

    def shock(self, indices):
        for j in sorted(set(indices)):
            if j < 0 or j >= self.n:
                raise IndexError("shock port")
            if self.up[j]:
                self.up[j] = False
                self.remaining[j] = self._draw(j)
                self.events.append((self.time, j, "FORCED_DOWN"))

    def advance(self, stop, lam, mu):
        """Return (start,end,online count) segments on [current, stop]."""
        if not np.isfinite([stop,lam,mu]).all() or stop < self.time or min(lam, mu) < 0:
            raise ValueError("Invalid time/rate")
        seg = []
        while self.time < stop:
            rates = np.where(self.up, lam, mu)
            wait = np.divide(self.remaining, rates, out=np.full(self.n, np.inf), where=rates>0)
            j = int(np.argmin(wait))
            step = min(float(wait[j]), stop-self.time)
            if step < 0:
                raise ArithmeticError("Negative hazard remainder")
            old = self.time
            self.time += step
            self.remaining = np.maximum(0., self.remaining-rates*step)
            if self.time > old:
                seg.append((old,self.time,int(self.up.sum())))
            if wait[j] <= step:  # includes a jump exactly at the endpoint
                self.up[j] = not self.up[j]
                self.events.append((self.time,j,"UP" if self.up[j] else "DOWN"))
                self.remaining[j] = self._draw(j)
        return seg


@dataclass
class Packet:
    id: int
    mass: float
    arrival: float
    task: float  # residual battery-side kWh per vehicle
    battery: float
    started: float = math.nan
    original_task: float = math.nan


class FractionalStation:
    """Fluid occupancy with FIFO admission and locked, power-limited service.

    Queue order concerns service starts, not completions of unequal tasks.
    No rounding of positive mass. Equivalent outage blocks change aggregate
    power; a separate per-vehicle cap prevents 2000 kW passenger-car service.
    This is a declared alternative to the manuscript's ideal fluid workload
    recursion; it must not silently replace the inherited engine.
    """
    def __init__(self, vehicle_kw=150., battery_capacity=60.):
        if vehicle_kw <= 0 or battery_capacity <= 0:
            raise ValueError("Positive physical caps required")
        self.vehicle_kw = vehicle_kw
        self.battery_capacity = battery_capacity
        self.queue = deque()
        self.active = []
        self.done = []
        self.time = 0.
        self.arrived_mass = 0.
        self.arrived_task = 0.
        self.served = 0.
        self.intervals = []
        self.start_ledger = []

    def arrive(self, packet):
        if packet.mass <= 0 or not np.isfinite([packet.mass,packet.arrival,packet.task,packet.battery]).all():
            raise ValueError("Positive finite vehicle mass and finite state required")
        if packet.arrival != self.time or packet.task < 0 or packet.battery < 0:
            raise ValueError("Arrivals must be at the current physical clock")
        if packet.battery + packet.task > self.battery_capacity + 1e-10:
            raise ValueError("Charging task exceeds battery headroom")
        p = replace(packet, original_task=packet.task)
        self.arrived_mass += p.mass
        self.arrived_task += p.mass*p.task
        if p.task == 0:
            self.done.append((p,self.time))
        else:
            self.queue.append(p)

    def _admit(self, power):
        room = max(0., power/self.vehicle_kw - math.fsum(p.mass for p in self.active))
        while self.queue and room > 0:
            p = self.queue[0]
            admitted = min(room,p.mass)
            x = replace(p,mass=admitted,started=self.time)
            self.active.append(x)
            self.start_ledger.append((p.id,p.arrival,self.time,admitted))
            if admitted == p.mass:
                self.queue.popleft()
            else:
                self.queue[0] = replace(p,mass=p.mass-admitted)
            room -= admitted

    def advance(self, stop, power_kw):
        if stop < self.time or power_kw < 0 or not np.isfinite([stop,power_kw]).all():
            raise ValueError("Invalid service interval")
        while self.time < stop:
            self._admit(power_kw)
            m = math.fsum(p.mass for p in self.active)
            rate = min(self.vehicle_kw,power_kw/m) / 60 if m>0 else 0.
            duration = stop-self.time
            first = min((p.task for p in self.active),default=math.inf)
            if rate>0:
                duration = min(duration,first/rate)
            if duration <= 0:
                raise ArithmeticError("Station did not advance")
            start = self.time
            supplied = 0.
            next_active = []
            for p in self.active:
                e = min(p.task,rate*duration)
                supplied += p.mass*e
                r = p.task-e
                x = replace(p,task=r,battery=p.battery+e)
                # Completion uses per-vehicle energy equality, never a mass cutoff.
                if r <= 1e-12*max(1.,p.original_task):
                    supplied += p.mass*r
                    x = replace(x,task=0.,battery=x.battery+r)
                    self.done.append((x,start+duration))
                else:
                    next_active.append(x)
            self.active = next_active
            self.time += duration
            self.served += supplied
            self.intervals.append((start,self.time,power_kw,m,supplied,rate*60))

    def balances(self):
        packets = list(self.queue)+self.active+[p for p,_ in self.done]
        rem = math.fsum(p.mass*p.task for p in list(self.queue)+self.active)
        return dict(mass_residual=math.fsum(p.mass for p in packets)-self.arrived_mass,
                    energy_residual=self.served+rem-self.arrived_task,
                    waiting_kwh=math.fsum(p.mass*p.task for p in self.queue),
                    service_kwh=math.fsum(p.mass*p.task for p in self.active),
                    completed_veh=math.fsum(p.mass for p,_ in self.done))


def wcl_step(battery, remaining_task, traction_kwh, power_kw, energized_minutes,
             capacity=60., efficiency=.9, min_battery=12.):
    """Simultaneous uniform traction/charging within an energized segment.

    Battery endpoint is clamped by physical headroom including traction.
    A downstream unpowered FIFO queue is passed with energized_minutes=0.
    The caller must split segments if trajectory/power changes inside them.
    """
    if not (0<=battery<=capacity and remaining_task>=0 and traction_kwh>=0 and
            power_kw>=0 and energized_minutes>=0 and 0<efficiency<=1):
        raise ValueError("Invalid WCL state")
    e = min(remaining_task, power_kw*efficiency*energized_minutes/60,
            max(0.,capacity-battery+traction_kwh))
    b = battery-traction_kwh+e
    if min(battery,b) < min_battery-1e-10:
        raise ValueError("Infeasible SOC trajectory; do not replace with a finite penalty")
    return b,remaining_task-e,e


def ctm_chain_step(n, capacity_veh_min, jam_veh, vf_dt_dx, w_dt_dx, dt,
                   upstream_demand, downstream_supply):
    """Godunov/CTM for one serial chain, with explicit boundary supplies.

    Does not define junction priorities or turn fractions for a network.
    Public BPR capacities are not automatically CTM discharge/storage data.
    """
    n,q,jam,v,w = [np.asarray(x,float) for x in
                    (n,capacity_veh_min,jam_veh,vf_dt_dx,w_dt_dx)]
    if not (n.shape==q.shape==jam.shape==v.shape==w.shape) or n.ndim!=1:
        raise ValueError("CTM shape mismatch")
    if dt<=0 or min(upstream_demand,downstream_supply)<0 or not np.isfinite(np.r_[n,q,jam,v,w,dt,upstream_demand,downstream_supply]).all():
        raise ValueError("Invalid CTM inputs")
    if np.any((n<0)|(n>jam)|(q<0)|(v<0)|(v>1)|(w<0)|(w>1)):
        raise ValueError("CTM state/CFL violation")
    sending = np.minimum(v*n,q*dt)
    receiving = np.minimum(w*(jam-n),q*dt)
    f = np.r_[min(upstream_demand*dt,receiving[0]),
              np.minimum(sending[:-1],receiving[1:]),min(sending[-1],downstream_supply*dt)]
    return n+f[:-1]-f[1:],f


def project_simplex(v,total):
    v=np.asarray(v,float)
    if total<0 or not np.isfinite(total) or not np.isfinite(v).all() or v.size==0:
        raise ValueError("Invalid simplex")
    if total==0:return np.zeros_like(v)
    u=np.sort(v.ravel())[::-1];s=np.cumsum(u)-total
    rho=np.nonzero(u-s/np.arange(1,len(u)+1)>0)[0][-1]
    return np.maximum(v-s[rho]/(rho+1),0.)


def vi_gap(flow,cost,groups):
    """Finite-alternative VI gap, with infeasible positive mass exposed."""
    f,c=np.asarray(flow,float),np.asarray(cost,float)
    if f.shape!=c.shape or f.ndim!=1:raise ValueError('Flow/cost dimension mismatch')
    if np.any(f<0) or not np.isfinite(f).all() or np.isnan(c).any():
        raise ValueError("Invalid flow/cost")
    numerator=0.;denom=0.;worst=0.
    infeasible=float(f[~np.isfinite(c)].sum())
    if infeasible>0:return dict(relative_gap=math.inf,absolute_gap=math.inf,worst_excess=math.inf,infeasible_mass=infeasible)
    for ix in groups:
        ix=np.asarray(ix,int); ok=np.isfinite(c[ix])
        if not ok.any():
            if f[ix].sum()>0:raise ValueError("No feasible continuation")
            continue
        cc=c[ix][ok];ff=f[ix][ok];excess=cc-cc.min()
        numerator+=float(ff@excess);denom+=float(ff@np.abs(cc))
        if (ff>0).any():worst=max(worst,float(excess[ff>0].max()))
    return dict(relative_gap=numerator/max(denom,1e-15),absolute_gap=numerator,
                worst_excess=worst,infeasible_mass=infeasible)


def solve_vi(oracle,groups,demands,initial,step=.1,max_iter=2000,tol=1e-8,flow_tol=1e-8):
    """Projected extragradient; final SAME-ITERATE costs and gap are returned.

    Convergence is not guaranteed for a general nonmonotone traffic oracle.
    Feasible alternatives must be fixed during one frozen-state solve. Inf
    is never replaced by a fabricated finite high cost. Oracle must return
    all alternatives, including zero-flow alternatives, without state writes.
    """
    if max_iter<1 or int(max_iter)!=max_iter or min(step,tol,flow_tol)<=0:raise ValueError('Invalid solver controls')
    x=np.asarray(initial,float).copy();groups=[np.asarray(g,int) for g in groups]
    flat=np.concatenate(groups)
    if len(flat)!=len(x) or len(np.unique(flat))!=len(x) or set(flat)!=set(range(len(x))):
        raise ValueError("Groups must partition flow indices")
    if len(groups)!=len(demands):raise ValueError("Demand dimension")
    def proj(v):
        out=np.zeros_like(v)
        for ix,d in zip(groups,demands):out[ix]=project_simplex(v[ix],d)
        return out
    x=proj(x);hist=[]
    c=np.asarray(oracle(x),float)
    if c.shape!=x.shape or not np.isfinite(c).all():raise ValueError("Restrict to feasible finite alternatives before solve")
    for k in range(max_iter):
        alpha=step
        for trial in range(35):
            y=proj(x-alpha*c);cy=np.asarray(oracle(y),float)
            if cy.shape!=x.shape or not np.isfinite(cy).all():raise ValueError("Oracle feasibility changed")
            if alpha*np.linalg.norm(cy-c)<=.7*np.linalg.norm(y-x)+1e-15:break
            alpha*=.5
        else:raise RuntimeError("Extragradient line search failed")
        new=proj(x-alpha*cy);delta=float(np.linalg.norm(new-x,1)/max(1.,sum(demands)))
        x=new;c=np.asarray(oracle(x),float)
        if c.shape!=x.shape or not np.isfinite(c).all():raise ValueError("Invalid final costs")
        g=vi_gap(x,c,groups)
        hist.append((k+1,g['relative_gap'],delta,alpha))
        if g['relative_gap']<=tol and delta<=flow_tol:break
    return dict(flow=x,cost=c,gap=g,history=np.array(hist),
                converged=g['relative_gap']<=tol and hist[-1][2]<=flow_tol)


def locked_candidates(executed,current_link,candidates,committed_station=None):
    """Ordered prefix INCLUDING an on-link activity is irrevocable."""
    prefix=tuple(executed)+(() if current_link is None else (current_link,))
    out=[]
    for i,c in enumerate(candidates):
        links=tuple(c['links'])
        if links[:len(prefix)]==prefix and (committed_station is None or c['station']==committed_station):out.append(i)
    return out


def dispatch_pool(scores,total):
    s=np.maximum(np.asarray(scores,float),0.)
    if total<0 or not np.isfinite(s).all() or not np.isfinite(total):raise ValueError("Invalid resource")
    return np.zeros_like(s) if s.sum()==0 else s*(total/s.sum())


def delay_resource(dispatch,delay_steps):
    y=np.asarray(dispatch,float)
    if int(delay_steps)!=delay_steps or delay_steps<0 or np.any(y<0):raise ValueError("Invalid delay/dispatch")
    out=np.zeros_like(y);d=int(delay_steps)
    if d==0:return y.copy()
    if d<len(y):out[d:]=y[:-d]
    return out


def discrete_repair_game(payoff,action_sets,initial,max_sweeps=100,tol=1e-8):
    """Finite-grid best responses with a fresh re-equilibrated payoff oracle.

    payoff(profile) must solve the entire selected continuation, then return
    one payoff per operator. The returned regret covers only supplied actions.
    Cycling/nonconvergence is returned, never relabelled as a Nash result.
    """
    p=list(initial);seen=set();trace=[]
    for sweep in range(max_sweeps):
        key=tuple(p)
        if key in seen:break
        seen.add(key);changed=False
        for i,actions in enumerate(action_sets):
            base=float(payoff(tuple(p))[i]);best=base;choice=p[i]
            for a in actions:
                test=p.copy();test[i]=a;u=float(payoff(tuple(test))[i])
                if not np.isfinite(u):raise ValueError("Invalid payoff continuation")
                if u>best+tol:best=u;choice=a
            if choice!=p[i]:p[i]=choice;changed=True
        trace.append(tuple(p))
        if not changed:break
    base=np.asarray(payoff(tuple(p)),float);reg=[]
    for i,actions in enumerate(action_sets):
        gains=[]
        for a in actions:
            test=p.copy();test[i]=a;gains.append(float(payoff(tuple(test))[i])-base[i])
        reg.append(max([0.]+gains))
    return dict(profile=tuple(p),regret=np.array(reg),grid_nash=max(reg)<=tol,trace=trace)


def weighted_quantile(values,weights,q):
    v,w=np.asarray(values,float),np.asarray(weights,float)
    if not 0<=q<=1 or np.any(w<0) or not np.isfinite(v).all() or not np.isfinite(w).all():raise ValueError("Invalid quantile")
    ok=w>0
    if not ok.any():return math.nan
    v,w=v[ok],w[ok];ix=np.argsort(v,kind='stable');v,w=v[ix],w[ix]
    return float(v[min(np.searchsorted(np.cumsum(w),q*w.sum(),side='left'),len(v)-1)])


def recovery_time(time,performance,event_time,threshold=.95,hold=10.):
    t,p=np.asarray(time,float),np.asarray(performance,float)
    if t.shape!=p.shape or len(t)<2 or np.any(np.diff(t)<=0):raise ValueError("Invalid time grid")
    for i in range(len(t)):
        if t[i]<event_time or t[i]+hold>t[-1]:continue
        j=np.searchsorted(t,t[i]+hold,side='left')
        if np.isfinite(p[i:j+1]).all() and (p[i:j+1]>=threshold).all():return float(t[i]-event_time),False
    return math.nan,True
