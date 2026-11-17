"""All eight manuscript figure families from audited formal results.

Input registry is a list of case directories. Each directory supplies a
certificate plus metrics.csv and timeseries.csv. No synthetic fallback.
Each metrics CSV contains replicate-level rows; matched comparisons must
already report paired effects (INT/PB/BR etc.) from matched physical runs.
"""
from pathlib import Path
import argparse,csv,json
import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from evidence import check_paper_case

# experiment, filename, x field, y field, result field, plot type
FIGURES=[('B','M01_AvailabilityResilience','scale','utilization','RI','map'),
 ('C','M02_AdaptationBoundary','theta','demand_multiplier','QSA','map'),
 ('D','M03_RepairInteraction','theta','repair_budget','INT_US','map'),
 ('E','M04_WCLBuffer','wcl_kw','loss_fraction','BR_WCL','map'),
 ('F','M05_Preparedness','preparedness','unused','RI','bar'),
 ('G','M06_Governance','repair_cost','governance','recovery_cost','scatter'),
 ('H','M07_PoolingDelay','pool_share','delay_min','PB','map'),
 ('I','M08_LowSOC','recovery_cost','priority','LSE','scatter')]

def publish(registry,out,comparison_id=None):
    registry=Path(registry).resolve();out=Path(out).resolve()
    if out.exists():raise FileExistsError('Use a new publication directory')
    cases=json.loads(registry.read_text());data=[]
    for entry in cases:
        folder=(registry.parent/entry).resolve();cert=check_paper_case(folder)
        with (folder/'metrics.csv').open(encoding='utf-8-sig') as f:rows=list(csv.DictReader(f))
        if not rows:raise ValueError('Empty formal metrics')
        for r in rows:
            if r.get('experiment')!=cert['experiment']:raise ValueError('Experiment certificate mismatch')
            if not r.get('seed') or not r.get('case_id'):raise ValueError('Missing replicate identity')
            if not r.get('comparison_id'):raise ValueError('Declare comparison_id for nuisance factors; do not average different designs')
            if comparison_id is not None and r['comparison_id']!=comparison_id:continue
            r['source_directory']=str(folder);data.append(r)
    out.mkdir(parents=True);status=[]
    for exp,name,x,y,z,kind in FIGURES:
        rows=[r for r in data if r['experiment']==exp]
        if not rows:
            status.append(dict(Figure=name,Status='MISSING_CERTIFIED_CASES',Experiment=exp));continue
        if len({r['comparison_id'] for r in rows})!=1:raise ValueError('Select a single comparison_id for each figure family')
        needed={x,z}|({y} if y!='unused' else set())
        if any(not needed<=set(r) or any(r[v]=='' for v in needed) for r in rows):raise ValueError('Figure field schema: '+name)
        if z in ('INT_US','BR_WCL','PB') and any(not r.get('paired_crn_id') or not r.get('baseline_case_id') for r in rows):
            raise ValueError('Paired mechanism effect lacks CRN/baseline identities')
        fig,ax=plt.subplots(figsize=(7,4.5))
        if kind=='map':
            xs=sorted(set(float(r[x]) for r in rows));ys=sorted(set(float(r[y]) for r in rows))
            values=np.full((len(ys),len(xs)),np.nan)
            for i,yy in enumerate(ys):
                for j,xx in enumerate(xs):
                    cell=[float(r[z]) for r in rows if float(r[x])==xx and float(r[y])==yy]
                    if not cell:raise ValueError('Incomplete certified map grid: '+name)
                    values[i,j]=np.mean(cell)
            if not np.isfinite(values).all():raise ValueError('Nonfinite scientific metric')
            im=ax.imshow(values,origin='lower',aspect='auto',cmap='viridis')
            ax.set_xticks(range(len(xs)),[f'{v:g}' for v in xs]);ax.set_yticks(range(len(ys)),[f'{v:g}' for v in ys]);fig.colorbar(im,ax=ax,label=z)
        elif kind=='bar':
            labels=sorted(set(r[x] for r in rows));means=[np.mean([float(r[z]) for r in rows if r[x]==s]) for s in labels]
            ax.bar(labels,means);ax.set_ylabel(z)
        else:
            for label in sorted(set(r[y] for r in rows)):
                sub=[r for r in rows if r[y]==label]
                ax.scatter(np.mean([float(r[x]) for r in sub]),np.mean([float(r[z]) for r in sub]),label=label)
            ax.set_ylabel(z);ax.legend(frameon=False)
        ax.set_xlabel(x)
        if kind=='map':ax.set_ylabel(y)
        ax.set_title(name.replace('_',' '));fig.tight_layout()
        fig.savefig(out/(name+'.svg'));fig.savefig(out/(name+'.png'),dpi=300);plt.close(fig)
        with (out/(name+'_data.csv')).open('w',newline='') as f:
            keys=sorted(set().union(*(r.keys() for r in rows)));w=csv.DictWriter(f,fieldnames=keys);w.writeheader();w.writerows(rows)
        status.append(dict(Figure=name,Status='GENERATED_FROM_AUDITED_INPUTS',Experiment=exp))
    with (out/'MANUSCRIPT_OUTPUT_STATUS.csv').open('w',newline='') as f:
        w=csv.DictWriter(f,fieldnames=['Figure','Status','Experiment']);w.writeheader();w.writerows(status)
    if any(r['Status']!='GENERATED_FROM_AUDITED_INPUTS' for r in status):
        print('Formal manuscript figures remain incomplete; see MANUSCRIPT_OUTPUT_STATUS.csv.')
    return status

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--registry',required=True);p.add_argument('--out',required=True);p.add_argument('--comparison-id');a=p.parse_args();publish(a.registry,a.out,a.comparison_id)
