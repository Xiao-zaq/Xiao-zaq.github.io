"""Regenerate actually computed reference results, tables and figures."""
from pathlib import Path
import argparse,csv,json,math,time,unittest,sys,io,hashlib
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from p4core import *
from network import Link,Traveler,load_fixed_flow
from evidence import import_p5p3

ROOT=Path(__file__).resolve().parents[1]
COLORS=['#215E87','#CA6B34','#368675','#935B8B','#8D8839']
plt.rcParams.update({'font.family':'DejaVu Sans','font.size':10,'axes.spines.top':False,
                     'axes.spines.right':False,'axes.prop_cycle':plt.cycler(color=COLORS),
                     'svg.fonttype':'none','figure.dpi':120,'savefig.dpi':180})

def table(out,name,rows):
    if not rows:raise ValueError('Empty output table '+name)
    with (out/'tables'/name).open('w',newline='',encoding='utf-8') as f:
        w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)

def save(fig,out,name,caption):
    fig.text(.5,.008,'REFERENCE / COMPONENT STUDY — not a certified V173 experiment',ha='center',fontsize=8,color='#666666')
    fig.tight_layout(rect=[0,.045,1,1])
    for ext in ['png','svg']:fig.savefig(out/'figures'/f'{name}.{ext}',bbox_inches='tight')
    plt.close(fig)
    return dict(file=name,caption=caption)

def run(out,mc):
    out=Path(out).resolve()
    if out.exists():raise FileExistsError('Outputs are immutable; select a new directory')
    if mc<2:raise ValueError('At least two Monte Carlo paths')
    out.mkdir(parents=True);(out/'figures').mkdir();(out/'tables').mkdir()
    started=time.perf_counter();figs=[]
    suite=unittest.defaultTestLoader.discover(str(ROOT/'python'),pattern='test_*.py')
    stream=io.StringIO();result=unittest.TextTestRunner(stream=stream,verbosity=2).run(suite)
    (out/'UNIT_TESTS.txt').write_text(stream.getvalue())
    if not result.wasSuccessful():raise RuntimeError('Unit test failure; results not released')
    table(out,'VALIDATION.csv',[dict(TestCount=result.testsRun,Failures=len(result.failures),Errors=len(result.errors),
                                  Scope='Python analytic/component/fixed-flow fixture',MATLAB='NOT_EXECUTED')])
    table(out,'EXECUTED_SOURCE_IDENTITY.csv',[dict(File=p.name,SHA256=hashlib.sha256(p.read_bytes()).hexdigest())
        for p in sorted((ROOT/'python').glob('*.py'))])
    print(f'{result.testsRun}/{result.testsRun} component tests passed',flush=True)
    # Public SF24 topology only: original EV path sequence/WCL placement absent.
    nodes=np.loadtxt(ROOT/'data/public/SiouxFalls_node.tntp',skiprows=1,usecols=(0,1,2))
    coords={int(i):(x,y) for i,x,y in nodes};edges=[]
    for row in (ROOT/'data/public/SiouxFalls_net.tntp').read_text().splitlines():
        a=row.replace(';','').split()
        if len(a)>=10 and a[0].isdigit():edges.append((int(a[0]),int(a[1])))
    fig,ax=plt.subplots(figsize=(7.1,5.1))
    for u,v in edges:
        ax.annotate('',xy=coords[v],xytext=coords[u],arrowprops=dict(arrowstyle='->',color='#B3BCC6',lw=.65,shrinkA=8,shrinkB=8))
    for i,(x,y) in coords.items():
        station=i in [3,10,15,24]
        ax.scatter(x,y,s=220 if station else 130,c='#CA6B34' if station else '#215E87',zorder=3)
        ax.text(x,y,str(i),ha='center',va='center',color='white',fontsize=8,zorder=4)
    ax.set_axis_off();ax.set_title('Public Sioux Falls base graph: 24 nodes, 76 links\nOrange: manuscript station locations; EV extensions not inferred')
    figs.append(save(fig,out,'R01_SF24_BASE_TOPOLOGY','Public benchmark graph only. No 107-path or 491-path mapping is asserted.'))
    # Analytical same-availability construction.
    scales=[.25,.5,1,2,4];rr=[];curves=[];T=180.;a=.97;p0=.5
    for c in scales:
        lam,mu=reliability_rates(a,60,c)
        expected=(1-a)*T+(a-p0)*(-math.expm1(-(lam+mu)*T))/(lam+mu)
        rr.append(dict(Scale=c,Availability=mu/(lam+mu),LambdaPerMin=lam,MuPerMin=mu,MTTFmin=1/lam,MTTRmin=1/mu,
                       ExpectedDownFractionAreaMin=expected))
        for t in range(181):curves.append(dict(Scale=c,TimeMin=t,ExpectedUpFraction=a+(p0-a)*math.exp(-(lam+mu)*t)))
    table(out,'EQUAL_AVAILABILITY_PARAMETERS.csv',rr);table(out,'EXPECTED_PORT_RECOVERY.csv',curves)
    fig,axs=plt.subplots(1,2,figsize=(8.2,3.5))
    axs[0].plot(scales,[r['MTTRmin'] for r in rr],'o-');axs[0].set(xscale='log',yscale='log',xlabel='Rate multiplier c',ylabel='MTTR (min)',title='Repair time scale')
    axs[1].plot(scales,[r['Availability'] for r in rr],'o-');axs[1].set(xscale='log',ylim=(.95,.99),xlabel='Rate multiplier c',ylabel='Long-run availability',title='Availability remains 0.97')
    figs.append(save(fig,out,'R02_AVAILABILITY_TIME_SCALE','a=0.97 and MTTR=60 min at c=1 are declared mechanism parameters.'))
    fig,ax=plt.subplots(figsize=(6.5,3.7))
    for c in scales:
        r=[x for x in curves if x['Scale']==c];ax.plot([x['TimeMin'] for x in r],[x['ExpectedUpFraction'] for x in r],label=f'c={c:g}')
    ax.axhline(a,color='gray',ls=':',lw=1);ax.set(xlabel='Time after forced outage (min)',ylabel='Expected online fraction',title='Exact two-state expectation after 50% outage');ax.legend(ncol=3,frameon=False)
    figs.append(save(fig,out,'R03_EXPECTED_RECOVERY','Initial state: exactly 10/20 components online. Curves are analytical, not traffic-network resilience.'))
    # Exact continuous-time Monte Carlo, common event-order streams per replicate.
    areas=np.empty((mc,len(scales)));raw=[]
    for j,c in enumerate(scales):
        lam,mu=reliability_rates(a,60,c)
        for i in range(mc):
            pc=PortClock(20,20261117+i);pc.shock(range(10));segments=pc.advance(T,lam,mu)
            area=math.fsum((end-start)*(1-up/20) for start,end,up in segments)
            areas[i,j]=area;raw.append(dict(Replicate=i+1,Seed=20261117+i,Scale=c,DownFractionAreaMin=area,
                                            NaturalFailures=sum(ev[2]=='DOWN' for ev in pc.events),Repairs=sum(ev[2]=='UP' for ev in pc.events)))
        print(f'Exact port Monte Carlo: c={c:g}, N={mc}',flush=True)
    table(out,'PORT_MC_RAW.csv',raw)
    rng=np.random.default_rng(3417);ix=rng.integers(0,mc,size=(2000,mc));means=areas[ix].mean(axis=1)
    summary=[]
    for j,c in enumerate(scales):
        delta=means[:,j]-means[:,2]
        summary.append(dict(Scale=c,N=mc,MeanDownArea=areas[:,j].mean(),AnalyticalDownArea=rr[j]['ExpectedDownFractionAreaMin'],
                            MeanCILow=np.quantile(means[:,j],.025),MeanCIHigh=np.quantile(means[:,j],.975),
                            PairedDifferenceVsC1=(areas[:,j]-areas[:,2]).mean(),PairedCILow=np.quantile(delta,.025),PairedCIHigh=np.quantile(delta,.975)))
    table(out,'PORT_MC_SUMMARY.csv',summary)
    fig,ax=plt.subplots(figsize=(6.5,3.7));ym=areas.mean(axis=0);lo=np.quantile(means,.025,axis=0);hi=np.quantile(means,.975,axis=0)
    ax.errorbar(range(5),ym,yerr=np.array([ym-lo,hi-ym]),fmt='o',capsize=5,label=f'Exact CTMC MC, N={mc}')
    ax.plot(range(5),[r['ExpectedDownFractionAreaMin'] for r in rr],'x--',label='Analytical expectation')
    ax.set(xticks=range(5),xticklabels=[str(c) for c in scales],xlabel='Rate multiplier c',ylabel='Unavailable-fraction area (min)',title='Analytical / Monte Carlo cross-check');ax.legend(frameon=False)
    figs.append(save(fig,out,'R04_MC_ANALYTIC_COMPARISON','95% percentile bootstrap intervals; same replicate indices are resampled for all rate scales.'))
    # FIFO fluid service fixture, deterministic power interruption.
    records=[];starts=[];fin=[]
    for shock in [False,True]:
        s=FractionalStation(150);label='50% power loss' if shock else 'No power loss'
        for t in range(180):
            if t<60:s.arrive(Packet(t,2.,float(t),12.,18.))
            power=300. if shock and 20<=t<50 else 600.
            s.advance(t+1,power);b=s.balances()
            records.append(dict(Case=label,TimeMin=t+1,PowerKW=power,WaitingKWh=b['waiting_kwh'],ServiceKWh=b['service_kwh'],CompletedVeh=b['completed_veh'],ServedKWh=s.served))
        for cid,arr,start,m in s.start_ledger:starts.append(dict(Case=label,Cohort=cid,ArrivalMin=arr,StartMin=start,MassVeh=m,WaitMin=start-arr))
        waits=[p.started-p.arrival for p,end in s.done];weights=[p.mass for p,end in s.done]
        fin.append(dict(Case=label,ArrivedVeh=s.arrived_mass,CompletedVeh=s.balances()['completed_veh'],ServedKWh=s.served,
                        MassResidual=s.balances()['mass_residual'],EnergyResidual=s.balances()['energy_residual'],
                        MeanWaitMin=np.average(waits,weights=weights),P95WaitMin=weighted_quantile(waits,weights,.95)))
    table(out,'FCS_FIXTURE_TIMESERIES.csv',records);table(out,'FCS_FIXTURE_SERVICE_STARTS.csv',starts);table(out,'FCS_FIXTURE_METRICS.csv',fin)
    fig,axs=plt.subplots(1,2,figsize=(9,3.8))
    for label in ['No power loss','50% power loss']:
        r=[x for x in records if x['Case']==label];tt=[x['TimeMin'] for x in r]
        axs[0].plot(tt,[x['WaitingKWh'] for x in r],label=label);axs[1].plot(tt,[x['CompletedVeh'] for x in r],label=label)
    for ax in axs:ax.axvspan(20,50,color='#EAB38E',alpha=.2);ax.set_xlabel('Time (min)')
    axs[0].set(ylabel='Waiting workload (kWh)',title='FIFO waiting stock');axs[1].set(ylabel='Completed mass (veh)',title='Service completion');axs[0].legend(frameon=False,fontsize=8)
    figs.append(save(fig,out,'R05_FCS_QUEUE_SERVICE','Isolated 600-kW station, 150-kW vehicle cap, 120 vehicles, 12 kWh/vehicle.'))
    tiny=[]
    for mass in [3.132786e-9,1e-6,.001,.1,1.]:
        s=FractionalStation();s.arrive(Packet(1,mass,0,30,18));s.advance(20,40000)
        tiny.append(dict(MassVeh=mass,ServiceMin=s.done[0][1],DeliveredKWh=s.served,PerVehicleKWh=s.served/mass))
    table(out,'FRACTIONAL_MASS_POWER.csv',tiny)
    fig,ax=plt.subplots(figsize=(6.5,3.7));ax.semilogx([r['MassVeh'] for r in tiny],[r['ServiceMin'] for r in tiny],'o-')
    ax.set(ylim=(0,15),xlabel='Cohort mass (veh)',ylabel='Per-vehicle service time (min)',title='Positive fractional mass retains a 12-minute service clock')
    figs.append(save(fig,out,'R06_MICRO_MASS_SERVICE','30 kWh / 150 kW = 12 min for every positive mass; energy is mass-weighted.'))
    # CTM chain fixture with real receiving constraint.
    n=np.zeros(6);ct=[];res=[]
    for t in range(100):
        before=n.sum();supply=0 if 20<=t<40 else 3
        n,f=ctm_chain_step(n,np.full(6,3.),np.full(6,12.),np.ones(6),np.full(6,.5),1,2.5 if t<60 else 0,supply)
        res.append(n.sum()-before-f[0]+f[-1])
        for j in range(6):ct.append(dict(TimeMin=t+1,Cell=j+1,OccupancyVeh=n[j],BoundaryOutVeh=f[j+1]))
    table(out,'CTM_CHAIN.csv',ct)
    fig,ax=plt.subplots(figsize=(6.5,3.7));arr=np.array([r['OccupancyVeh'] for r in ct]).reshape(100,6).T
    im=ax.imshow(arr,origin='lower',aspect='auto',extent=[0,100,.5,6.5],cmap='YlGnBu',vmin=0,vmax=12);fig.colorbar(im,ax=ax,label='Occupancy (veh)')
    ax.set(xlabel='Time (min)',ylabel='Cell',title='CTM receiving constraint under downstream closure')
    figs.append(save(fig,out,'R07_CTM_SPILLBACK_FIXTURE','Serial 6-cell component test. Full-network junction/spillback calibration is not supplied.'))
    # Known-solution VI, not a dynamic traffic network VI.
    vi=solve_vi(lambda x:np.array([2+2*x[0],5+x[1]]),[[0,1]],[10],[10,0],step=.4)
    table(out,'VI_CONVERGENCE.csv',[dict(Iteration=int(k),RelativeGap=g,FlowChange=d,Step=al) for k,g,d,al in vi['history']])
    table(out,'VI_SOLUTION.csv',[dict(Alternative=i+1,Flow=x,Cost=c,AnalyticalFlow=a) for i,(x,c,a) in enumerate(zip(vi['flow'],vi['cost'],[13/3,17/3]))])
    fig,ax=plt.subplots(figsize=(6.5,3.7));ax.semilogy(vi['history'][:,0],vi['history'][:,1],label='Same-iterate VI gap');ax.semilogy(vi['history'][:,0],vi['history'][:,2],label='Normalized flow change')
    ax.set(xlabel='Iteration',ylabel='Residual',title='Extragradient solver on an analytic two-route VI');ax.legend(frameon=False)
    figs.append(save(fig,out,'R08_VI_ANALYTIC_FIXTURE','Analytical solution is [13/3, 17/3] vehicles. No V173 equilibrium is inferred.'))
    wc=[]
    for wait in [0,5,10,20,40]:
        b,r,e=wcl_step(18,36,2,60,4);wc.append(dict(DownstreamWaitMin=wait,EnergizedMin=4,BatteryKWh=b,DeliveredKWhPerVeh=e))
    table(out,'WCL_LOCATION_CONTRACT.csv',wc)
    fig,ax=plt.subplots(figsize=(6.5,3.7));ax.plot([r['DownstreamWaitMin'] for r in wc],[r['DeliveredKWhPerVeh'] for r in wc],'o-');ax.set(ylim=(0,5),xlabel='Wait outside energized segment (min)',ylabel='WCL energy (kWh/veh)',title='Unpowered downstream waiting adds no WCL energy')
    figs.append(save(fig,out,'R09_WCL_LOCATION','4 powered minutes at 60 kW and 0.9 efficiency gives 3.6 battery-side kWh.'))
    yy=np.array([dispatch_pool([1,2,1],2) if k<6 else dispatch_pool([3,1,0],2) for k in range(12)]);ap=delay_resource(yy,2)
    table(out,'POOL_MOBILIZATION.csv',[dict(ControlIndex=k,ControlMinutes=5,Station=s,Planned=yy[k,s],Applied=ap[k,s],DelayMinutes=10) for k in range(12) for s in range(3)])
    fig,ax=plt.subplots(figsize=(6.5,3.7));ax.step(np.arange(12)*5,yy.sum(axis=1),where='post',label='Dispatched');ax.step(np.arange(12)*5,ap.sum(axis=1),where='post',label='Arrived after 10 min');ax.set(xlabel='Time (min)',ylabel='Normalized resource units',title='Pooled resources become effective only after arrival');ax.legend(frameon=False)
    figs.append(save(fig,out,'R10_POOL_DELAY','Control intervals last five minutes. Delayed resources are shifted, not duplicated.'))
    # Full link traversal fixture exercises the integrated fixed-flow loader.
    links=[Link(1,1,2,'ROAD',2,2,1),Link(2,2,3,'WCL',2,2,1,60),Link(3,3,4,'FCS',station=0),Link(4,4,5,'EXIT',1,0)]
    net=load_fixed_flow(links,[Traveler(1,2.5,0,(1,2,3,4),18,9),Traveler(2,3.132786e-9,1,(1,2,3,4),45,9)],60,lambda s,t:300)
    table(out,'FIXED_FLOW_LINK_TRACE.csv',net['trace']);table(out,'FIXED_FLOW_TIMESERIES.csv',net['timeseries'])
    summary=dict(version='P4_RESEARCH_V1',date='2026-11-17',scope='REFERENCE_COMPONENT_AND_FIXED_FLOW_FIXTURE',
                 tests_passed=result.testsRun,matlab_executed=False,monte_carlo_replicates=mc,
                 port_paths=5*mc,full_network_sf24_dnl_calls=0,formal_due_calls=0,historical_135_runs=0,
                 ctm_mass_residual_max=max(map(abs,res)),fixedflow_mass_residual=net['mass_residual'],
                 fixedflow_fcs_energy_residual=net['fcs_energy_residual'],figures=len(figs),
                 original_p5p3_bytes_included=False,production_admission='CLOSED',runtime_seconds=time.perf_counter()-started)
    (out/'RUN_SUMMARY.json').write_text(json.dumps(summary,indent=2))
    (out/'FIGURE_CATALOG.json').write_text(json.dumps(figs,indent=2))
    cards=''.join(f'<article><h2>{f["file"]}</h2><img src="figures/{f["file"]}.svg"><p>{f["caption"]}</p></article>' for f in figs)
    html='''<!doctype html><html lang="en"><meta charset="utf-8"><title>P4 reference results</title><style>body{font:16px/1.6 system-ui;color:#193044;margin:40px auto;max-width:1050px;padding:0 24px}h1{font-size:32px}article{margin:38px 0;border-top:1px solid #ddd;padding-top:12px}img{max-width:100%}h2{font-size:18px}aside{background:#eef4f8;padding:18px}code{font-size:13px}</style><h1>P4 reproducible reference results</h1><aside>These figures are computed analytical, Monte Carlo and component tests. They do not replace the original 107-path SF24 experiment, its pre-event DUE, rolling DUE or repair-governance results. Production admission remains CLOSED.</aside>'''+cards+'</html>'
    (out/'index.html').write_text(html,encoding='utf8')
    print(json.dumps(summary,indent=2),flush=True)
    return summary

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--out',required=True);parser.add_argument('--mc',type=int,default=1000);parser.add_argument('--p5p3-zip')
    args=parser.parse_args()
    if args.p5p3_zip:print(json.dumps(import_p5p3(args.p5p3_zip,args.out),indent=2))
    else:run(args.out,args.mc)
