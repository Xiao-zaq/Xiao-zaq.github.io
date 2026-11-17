"""Explicit metric definitions; no synthetic substituted equilibrium metrics."""
import numpy as np

def paired_workload(wait,service,base_wait,base_service,dt):
    q,s,q0,s0=[np.asarray(x,float) for x in (wait,service,base_wait,base_service)]
    if not (q.shape==s.shape==q0.shape==s0.shape) or dt<=0:raise ValueError('Matched workload arrays required')
    if not np.isfinite(np.r_[q.ravel(),s.ravel(),q0.ravel(),s0.ravel()]).all():raise ValueError('Nonfinite stock')
    if min(q.min(),s.min(),q0.min(),s0.min())<0:raise ValueError('Negative physical stock')
    QSA=float(np.maximum(q-q0,0).sum()*dt);SSA=float(np.maximum(s-s0,0).sum()*dt)
    return dict(QSA=QSA,SSA=SSA,WLA=QSA+SSA,WLA_net=float(np.maximum(q+s-q0-s0,0).sum()*dt))

def interaction(loss_none,loss_user,loss_repair,loss_joint):
    # Same shock/seed and same cost units required by calling experiment.
    return np.asarray(loss_user)+np.asarray(loss_repair)-np.asarray(loss_joint)-np.asarray(loss_none)

def relative_benefit(reference,alternative):
    a,b=np.broadcast_arrays(np.asarray(reference,float),np.asarray(alternative,float))
    return np.divide(a-b,a,out=np.full_like(a,np.nan),where=a>0)

def priority_gap(local,coordinated):
    a,b=np.asarray(local,float),np.asarray(coordinated,float)
    if a.shape!=b.shape or np.any(a<0) or np.any(b<0):raise ValueError('Invalid resource vectors')
    if a.sum()==0 or b.sum()==0:return float('nan')
    return float(.5*np.abs(a/a.sum()-b/b.sum()).sum())

def paired_bootstrap(effects,seed=731,replicates=2000):
    """Rows are matched seeds; columns are reported contrasts. No resampling arms independently."""
    d=np.asarray(effects,float)
    if d.ndim==1:d=d[:,None]
    if len(d)<2 or not np.isfinite(d).all():raise ValueError('At least two complete paired seeds')
    ix=np.random.default_rng(seed).integers(0,len(d),(replicates,len(d)))
    b=d[ix].mean(axis=1)
    return d.mean(axis=0),np.quantile(b,.025,axis=0),np.quantile(b,.975,axis=0)
