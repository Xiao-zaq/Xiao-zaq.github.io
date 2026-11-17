"""Read-only frozen evidence import. No model execution or archive overwrite."""
import csv,hashlib,json,zipfile,shutil
from pathlib import Path
import numpy as np
from scipy.io import loadmat

REQUIRED={
 'P5P3_EXACT_SAVED_FLOW_WITNESS.mat':'7367524514b11a4e8424ee2063b47f69090f8bce211a55d9ea1992868d012ce4',
 'P5P3_DEPARTURE_COHORT_MAPPING.csv':'b49266154f57adb94164ff956637b7403973f38cd4bd53846e1b4d09457c0a1f',
 'P5P3_DEPARTURE_TIME_CLASS_TOTAL.csv':'8729aba734022a8d60b1013e504d656433e6f45cd9e014984538f1a8641292fa'}

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def import_p5p3(archive,destination):
    archive=Path(archive).resolve();destination=Path(destination).resolve()
    if destination.exists():raise FileExistsError('Use a fresh output directory')
    with zipfile.ZipFile(archive) as z:
        names=z.namelist()
        if len(names)!=len(set(names)):raise ValueError('Duplicate archive member')
        if any(Path(n).name!=n or '\\' in n for n in names):raise ValueError('Flat expected archive only')
        if z.testzip():raise ValueError('CRC failure')
        manifest=list(csv.DictReader(z.read('P5P3_EVIDENCE_MANIFEST.csv').decode('utf-8-sig').splitlines()))
        if len(manifest)!=12 or set(names)!={r['RelativePath'] for r in manifest}|{'P5P3_EVIDENCE_MANIFEST.csv'}:
            raise ValueError('Manifest membership mismatch')
        for r in manifest:
            b=z.read(r['RelativePath'])
            if len(b)!=int(r['Bytes']) or hashlib.sha256(b).hexdigest().lower()!=r['SHA256'].lower():raise ValueError('Member identity mismatch')
        for name,h in REQUIRED.items():
            if hashlib.sha256(z.read(name)).hexdigest()!=h:raise ValueError('Frozen external anchor mismatch '+name)
        import io
        m=loadmat(io.BytesIO(z.read('P5P3_EXACT_SAVED_FLOW_WITNESS.mat')))
        F=m['Fstar']
        if F.shape!=(107,2,241) or not np.isfinite(F).all() or (F<0).any():raise ValueError('Invalid exact F')
        rows=list(csv.DictReader(z.read('P5P3_DEPARTURE_COHORT_MAPPING.csv').decode('utf-8-sig').splitlines()))
        rec=np.zeros_like(F);seen=set()
        for r in rows:
            ix=tuple(int(r[k])-1 for k in ['PathID','SOCClassID','DepartureTimeIndex'])
            if ix in seen:raise ValueError('Duplicate cohort cell')
            seen.add(ix);rec[ix]=float(r['MassVeh'])
        if len(rows)!=7538 or np.count_nonzero(F)!=7538:raise ValueError('Positive count mismatch')
        if not np.array_equal(rec>0,F>0) or not np.allclose(rec,F,rtol=1e-12,atol=1e-15):raise ValueError('CSV/exact tensor mismatch')
        if abs(F.sum()-3620)>1e-8:raise ValueError('Total demand mismatch')
        np.testing.assert_allclose(F.sum(axis=(0,2)),[2534,1086],atol=1e-8,rtol=0)
        acc=list(csv.DictReader(z.read('P5P3_INDEPENDENT_SAVED_ACCEPTANCE.csv').decode('utf-8-sig').splitlines()))
        if len(acc)!=17 or not all(r['Pass'].strip().lower() in ('1','true') for r in acc):raise ValueError('Original acceptance not 17/17')
        links=list(csv.DictReader(z.read('P5P3_LINK_CAPACITY_AND_PATH_INCIDENCE.csv').decode('utf-8-sig').splitlines()))
        if len(links)!=104:raise ValueError('Link inventory mismatch')
        traffic=[r for r in links if r['Kind'] in ('ROAD','WCL')]
        if len(traffic)!=96:raise ValueError('Traffic link count mismatch')
        diff=max(abs(float(r['DeparturePathIncidenceVeh'])-float(r['SavedIntegratedRoadVolumeVeh'])) for r in traffic)
        if diff>1e-8:raise ValueError('Integrated incidence mismatch')
        destination.mkdir(parents=True)
        for n in names:(destination/n).write_bytes(z.read(n))
    # Byte preservation follows validation; original remains unchanged.
    shutil.copyfile(archive,destination/'ORIGINAL_P5P3.zip')
    status=dict(status='P5P3_MAPPING_TECHNICAL_ONLY',archive_sha256=sha(archive),
                mass_veh=float(F.sum()),positive_cells=int(np.count_nonzero(F)),
                tiny_positive_cells=int(np.sum((F>0)&(F<1e-8))),
                link_integrated_difference=diff,production_admission='CLOSED')
    (destination/'IMPORT_REPORT.json').write_text(json.dumps(status,indent=2),encoding='utf8')
    return status


def check_paper_case(folder):
    """Verify provenance + explicit scientific gates before publication.

    Certificates are assertions by their issuing auditor, not generated here.
    SHA identity alone does not certify science. All referenced files are hashed.
    """
    folder=Path(folder).resolve()
    c=json.loads((folder/'certificate.json').read_text())
    mandatory=['pre_event_due','physical_mass','energy_soc','fifo','nonanticipativity',
               'residual_due','repair_clock','power_units','paired_shock','resource_budget']
    if c.get('governance') in ['G1','G2']:mandatory+=['repair_grid_regret']
    if c.get('experiment')=='F':mandatory+=['preparedness_state_identity']
    if c.get('scope')!='FORMAL_P4' or any(c.get('gates',{}).get(k)!='PASS' for k in mandatory):
        raise ValueError('Formal scientific gates not satisfied')
    for name,h in c.get('files',{}).items():
        p=(folder/name).resolve()
        if not p.is_relative_to(folder) or sha(p)!=h:raise ValueError('Certificate byte identity mismatch')
    if not {'metrics.csv','timeseries.csv'}<=set(c.get('files',{})):raise ValueError('Missing metric/series identity')
    if not c.get('auditor') or not c.get('source_commit'):raise ValueError('Missing issuing provenance')
    return c
