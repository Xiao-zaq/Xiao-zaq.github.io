"""Discrete-time continuous-mass fixed-flow network loader.

Roads use infinite-storage FIFO point queues with explicitly supplied physical
discharge capacities. This is NOT the Han LWR solver and not a spillback model.
Every link traversed is logged; WCL power acts only in the moving segment.
FCS service uses FractionalStation. Node transfers occur on dt boundaries.
"""
from dataclasses import dataclass,replace
from collections import deque
import math
import numpy as np
from p4core import Packet,FractionalStation,wcl_step

@dataclass(frozen=True)
class Link:
    id:int
    tail:int
    head:int
    kind:str
    fft_min:float=1.
    length_km:float=1.
    discharge_veh_min:float=10.
    wcl_kw:float=0.
    station:int=-1

@dataclass
class Traveler:
    id:int
    mass:float
    depart:float
    path:tuple
    battery:float
    task:float
    position:int=0
    enter:float=0.
    steps:int=0

def load_fixed_flow(links,travelers,horizon,station_power,dt=1.,vehicle_kw=150.,
                    battery_capacity=60.,min_battery=12.,energy_per_km=.2):
    if dt<=0 or horizon<=0 or abs(horizon/dt-round(horizon/dt))>1e-10:raise ValueError('Time grid')
    net={l.id:l for l in links}
    if len(net)!=len(links):raise ValueError('Duplicate link ID')
    for l in links:
        if l.kind not in ('ROAD','WCL','FCS','EXIT'):raise ValueError('Link kind')
        if l.kind in ('ROAD','WCL') and (l.fft_min<=0 or l.length_km<0 or l.discharge_veh_min<=0):raise ValueError('Physical road parameters required')
    work=[replace(p,path=tuple(p.path)) for p in travelers]
    if len({p.id for p in work})!=len(work):raise ValueError('Unique source cohort IDs required')
    for p in work:
        if p.mass<=0 or not np.isfinite([p.mass,p.depart,p.battery,p.task]).all() or p.task<0 or not p.path:raise ValueError('Invalid cohort')
        if not (min_battery<=p.battery<=battery_capacity):raise ValueError('Initial battery')
        if p.depart<0 or p.depart>=horizon or abs(p.depart/dt-round(p.depart/dt))>1e-10:raise ValueError('Departure grid')
        route=[net[k] for k in p.path]
        if any(a.head!=b.tail for a,b in zip(route[:-1],route[1:])):raise ValueError('Discontinuous route')
    roads={l.id:deque() for l in links if l.kind in ('ROAD','WCL','EXIT')}
    station_ids={l.station for l in links if l.kind=='FCS'}
    stations={i:FractionalStation(vehicle_kw,battery_capacity) for i in station_ids}
    templates={};station_done={i:0 for i in station_ids};next_sid=0
    trace=[];done=[];infeasible=[];series=[];future={}
    for p in work:future.setdefault(round(p.depart/dt),[]).append(p)
    def enter(p,t):
        nonlocal next_sid
        if p.position==len(p.path):
            if p.task>1e-9:infeasible.append((p,t,'TERMINAL_TASK'))
            else:done.append((p,t))
            return
        lid=p.path[p.position];l=net[lid];p=replace(p,enter=t,steps=0)
        if l.kind=='FCS':
            if p.task==0:
                trace.append(dict(id=p.id,link=lid,position=p.position,mass=p.mass,entry=t,exit=t,
                                  battery=p.battery,remaining_task=0.))
                enter(replace(p,position=p.position+1),t)
                return
            sid=next_sid;next_sid+=1;templates[sid]=p
            stations[l.station].arrive(Packet(sid,p.mass,t,p.task,p.battery))
        else:roads[lid].append(p)
    for k in range(round(horizon/dt)):
        t=k*dt;end=t+dt
        for p in sorted(future.pop(k,[]),key=lambda p:p.id):enter(p,t)
        moving=[];drive=0.;wireless=0.
        for lid,q in roads.items():
            l=net[lid];nstep=max(1,math.ceil(l.fft_min/dt-1e-12));updated=deque()
            for p in q:
                if p.steps<nstep and l.kind!='EXIT':
                    de=energy_per_km*l.length_km/nstep
                    try:
                        b,r,e=wcl_step(p.battery,p.task,de,l.wcl_kw if l.kind=='WCL' else 0,
                                       dt,battery_capacity,.9,min_battery)
                    except ValueError:
                        infeasible.append((p,end,'ON_LINK_SOC'));continue
                    p=replace(p,battery=b,task=r,steps=p.steps+1)
                    drive+=p.mass*de;wireless+=p.mass*e
                elif l.kind=='EXIT':p=replace(p,steps=p.steps+1)
                updated.append(p)
            roads[lid]=updated;q=updated
            budget=l.discharge_veh_min*dt if l.kind!='EXIT' else math.inf
            while q and q[0].steps>=nstep and budget>0:
                p=q[0];mass=min(p.mass,budget);part=replace(p,mass=mass)
                if mass==p.mass:q.popleft()
                else:q[0]=replace(p,mass=p.mass-mass)
                budget-=mass
                trace.append(dict(id=p.id,link=lid,position=p.position,mass=mass,entry=p.enter,exit=end,
                                  battery=part.battery,remaining_task=part.task))
                moving.append(replace(part,position=p.position+1))
        for sid,s in stations.items():
            power=float(station_power(sid,t))
            s.advance(end,power)
            for a,finish in s.done[station_done[sid]:]:
                p=templates[a.id];x=replace(p,mass=a.mass,battery=a.battery,task=0.)
                trace.append(dict(id=p.id,link=p.path[p.position],position=p.position,mass=a.mass,
                                  entry=p.enter,exit=finish,battery=x.battery,remaining_task=0.))
                moving.append(replace(x,position=x.position+1))
            station_done[sid]=len(s.done)
        # All receiving links are entered AFTER all outgoing links were advanced.
        for p in moving:enter(p,end)
        series.append(dict(time=end,road_veh=sum(p.mass for q in roads.values() for p in q),
                           waiting_kwh=sum(s.balances()['waiting_kwh'] for s in stations.values()),
                           service_kwh=sum(s.balances()['service_kwh'] for s in stations.values()),
                           completed_veh=sum(p.mass for p,_ in done),drive_kwh=drive,wcl_kwh=wireless))
    active_mass=sum(p.mass for q in roads.values() for p in q)+sum(p.mass for s in stations.values() for p in list(s.queue)+s.active)
    completed=sum(p.mass for p,_ in done);failed=sum(p.mass for p,_,_ in infeasible)
    admitted=sum(p.mass for p in work)
    rem_mass=sum(p.mass for ps in future.values() for p in ps)
    balance=completed+failed+active_mass+rem_mass-admitted
    return dict(trace=trace,timeseries=series,completed=done,infeasible=infeasible,
                mass_residual=balance,uncompleted_mass=active_mass+rem_mass,
                fcs_energy_residual=max([abs(s.balances()['energy_residual']) for s in stations.values()]+[0.]),
                scope='ISOLATED_FIXED_FLOW_POINT_QUEUE_NOT_FORMAL_SF24')
