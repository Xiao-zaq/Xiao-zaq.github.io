"""Verify final archive contents and saved numerical evidence independently."""
from pathlib import Path
import csv,hashlib,json,math
import numpy as np

root=Path(__file__).resolve().parent
with (root/'MANIFEST.csv').open() as f:manifest=list(csv.DictReader(f))
seen=set()
for r in manifest:
    p=(root/r['RelativePath']).resolve()
    assert p.is_relative_to(root) and r['RelativePath'] not in seen
    seen.add(r['RelativePath']);b=p.read_bytes()
    assert len(b)==int(r['Bytes']) and hashlib.sha256(b).hexdigest()==r['SHA256'],str(p)
actual={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file()
        and '__pycache__' not in p.parts and 'runs' not in p.relative_to(root).parts
        and '.git' not in p.relative_to(root).parts and p.name!='MANIFEST.csv'}
assert actual==seen,('Unmanifested or missing files',actual^seen)
d=root/'results/REFERENCE_20261117';tab=d/'tables'
def read(name):
    with (tab/name).open() as f:return list(csv.DictReader(f))
raw=read('PORT_MC_RAW.csv');summary=read('PORT_MC_SUMMARY.csv')
for r in summary:
    c=float(r['Scale']);x=np.array([float(z['DownFractionAreaMin']) for z in raw if float(z['Scale'])==c]);assert len(x)==int(r['N'])
    assert abs(x.mean()-float(r['MeanDownArea']))<1e-11
    mu=c/60;lam=mu*.03/.97;expected=.03*180+.47*(-math.expm1(-(lam+mu)*180))/(lam+mu)
    assert abs(expected-float(r['AnalyticalDownArea']))<1e-11
    assert abs(x.mean()-expected)<5*x.std(ddof=1)/math.sqrt(len(x)), 'Monte Carlo mean incompatible with analytic reference'
for r in read('FCS_FIXTURE_METRICS.csv'):
    assert abs(float(r['EnergyResidual']))<1e-8 and abs(float(r['MassResidual']))<1e-9
    assert abs(float(r['CompletedVeh'])-120)<1e-8 and abs(float(r['ServedKWh'])-1440)<1e-8
for r in read('FRACTIONAL_MASS_POWER.csv'):
    assert abs(float(r['ServiceMin'])-12)<1e-12
    assert abs(float(r['DeliveredKWh'])/float(r['MassVeh'])-30)<1e-10
trace=read('FIXED_FLOW_LINK_TRACE.csv')
for cohort,mass in [(1,2.5),(2,3.132786e-9)]:
    for link in range(1,5):
        y=sum(float(r['mass']) for r in trace if int(r['id'])==cohort and int(r['link'])==link)
        assert abs(y-mass)<max(1e-18,mass*1e-12)
assert len(list((d/'figures').glob('*.svg')))==10 and len(list((d/'figures').glob('*.png')))==10
status=json.loads((d/'RUN_SUMMARY.json').read_text());assert status['production_admission']=='CLOSED'
assert status['formal_due_calls']==0 and status['historical_135_runs']==0
print(f'PACKAGE {len(manifest)}/{len(manifest)} hashes PASS; saved independent numeric checks PASS.')
print('Formal SF24, rolling DUE, governance experiments and MATLAB execution remain unverified.')
