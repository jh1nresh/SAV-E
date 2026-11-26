"""Join frozen OSM use/material evidence to unchanged surveyed geometry.
A classification controls illustrative paint, never building shape or measured height.
Unknown or conflicting evidence stays generic; landmarks/schools are protected.
"""
import argparse,collections,gzip,hashlib,json,math
from pathlib import Path
import numpy as np
from shapely.geometry import Polygon,Point
from shapely.strtree import STRtree
HERE=Path(__file__).resolve().parent
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--scenes',type=Path,required=True,help='Frozen 7047 Pocket City scene JSON.gz directory')
parser.add_argument('--map-root',type=Path,default=HERE.parent.parent)
args=parser.parse_args()
SCENES=args.scenes.resolve()
assert len(list(SCENES.glob('*.json.gz')))==7047, 'Expected the full frozen Taipei scene set'
GLOBE=args.map_root.resolve()
OUT=GLOBE/'assets/pocket-survey/classes'
OUT.mkdir(parents=True,exist_ok=True)
RES={'apartments','residential','house','detached','terrace','dormitory','bungalow','semidetached_house'}
PROTECT={'school','university','college','kindergarten','temple','church','shrine','chapel','cathedral','religious','pagoda','museum','stadium'}
EARTH=40075016.68557849
polys=[];families=[];ids=[];skipped=0;source_hash=hashlib.sha256()
def family(b):
    if b.get('famous') or b.get('type') in PROTECT or b.get('use') in {'place_of_worship','museum','arts_centre','educational_institution'}:return 3
    if b.get('mat') in {'glass','mirror'}:return 2
    if b.get('type') in RES or b.get('use')=='apartment':return 1
    return 0
for f in sorted(SCENES.glob('*.json.gz')):
    raw=f.read_bytes();source_hash.update(f.name.encode());source_hash.update(raw)
    scene=json.loads(gzip.decompress(raw));m=scene['meta'];a=math.radians(m['rotation']);c,s=math.cos(a),math.sin(a);kx=111320*math.cos(math.radians(m['lat']))
    def ring(points):
        out=[]
        for x,y in points:
            lon=m['lon']+(c*x-s*y)/kx;lat=m['lat']+(s*x+c*y)/110574
            out.append(((lon+180)/360*EARTH,(1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*EARTH))
        return out
    for b in scene['buildings']:
        p=Polygon(ring(b['ring']),[ring(r) for r in b.get('holes',[])])
        if not p.is_valid or p.is_empty or p.area<.1:skipped+=1;continue
        polys.append(p);families.append(family(b));ids.append(b['id'])
print('OSM source footprints',len(polys),'invalid skipped',skipped,flush=True)
tree=STRtree(polys)
survey=json.loads((GLOBE/'data/survey-index.json').read_bytes())['levels']['200']
counts=collections.Counter();records={};witnesses={}
for i,t in enumerate(survey):
    raw=gzip.decompress((GLOBE/f"data/200/{t['id']}.bin.gz").read_bytes());v=np.frombuffer(raw,dtype='<f4').reshape(-1,6)
    starts=np.r_[0,np.flatnonzero(np.any(v[1:,3:]!=v[:-1,3:],axis=1))+1,len(v)]
    classes=np.zeros(len(v),dtype='u1');local=collections.Counter()
    for start,end in zip(starts[:-1],starts[1:]):
        assert start%3==0 and end%3==0
        tris=v[start:end,:3].reshape(-1,3,3).astype('float64');xy=tris[:,:,:2]
        area=np.abs((xy[:,1,0]-xy[:,0,0])*(xy[:,2,1]-xy[:,0,1])-(xy[:,1,1]-xy[:,0,1])*(xy[:,2,0]-xy[:,0,0]))
        if area.max()<.02:local['noInteriorTriangle']+=1;continue
        # A triangle centroid is inside the actual footprint, including concave/courtyard shells.
        # Query representative points across up to three largest roof triangles; conflict => unknown.
        candidates=np.argsort(area)[-3:];evidence=set();matched=[];complete=True
        for tri in candidates:
            if area[tri]<.02:continue
            x,y=xy[tri].mean(axis=0)
            p=Point((t['mx']+x*t['m'])*EARTH,(t['my']-y*t['m'])*EARTH)
            hits=tree.query(p,predicate='within')
            if len(hits)==0:complete=False
            # All containing source records must agree; do not select an arbitrary overlapping shop.
            evidence.update(families[j] for j in hits);matched.extend(ids[j] for j in hits)
        if len(evidence)==1 and complete:
            f=next(iter(evidence));classes[start:end]=f;local['matched']+=1;local[f'family{f}']+=1
            if f not in witnesses:witnesses[f]={'tile':t['id'],'start':int(start),'end':int(end),'sourceIds':sorted(set(matched)),'height':float(v[start,4])}
        else:local['conflict' if len(evidence)>1 else 'partial' if evidence else 'unmatched']+=1
    # One byte per source vertex, compressed runs; triangles always have one family.
    assert np.all(classes.reshape(-1,3)==classes.reshape(-1,3)[:,0,None])
    packed=gzip.compress(classes.tobytes(),mtime=0)
    (OUT/(t['id']+'.bin.gz')).write_bytes(packed)
    counts.update(local)
    records[t['id']]={'vertices':len(v),'meshSHA256':hashlib.sha256(raw).hexdigest(),'classSHA256':hashlib.sha256(classes).hexdigest(),'gzipBytes':len(packed),'counts':dict(local)}
    if i%800==0:print('mesh classes',i,'/',len(survey),dict(counts),flush=True)
report={'source':'Frozen OSM scene footprint/use/material join to municipal LOD1 geometry','sourceSceneSHA256':source_hash.hexdigest(),'sourceFootprints':len(polys),'invalidSourceFootprintsSkipped':skipped,'families':{'0':'generic illustrative office pattern; no asserted use','1':'mapped residential; illustrative apartment windows','2':'mapped glass/mirror material; illustrative curtain wall','3':'protected landmark/school/religious; retain prior material'},'counts':dict(counts),'witnesses':witnesses,'tiles':records,'geometryUnchanged':True,'unknownPolicy':'Conflicting or absent semantics stay generic, not inferred from height.'}
manifest={'schema':1,'encoding':'gzip uint8 family per vertex','families':report['families'],'sourceSceneSHA256':report['sourceSceneSHA256'],'tiles':sorted(records)}
(OUT/'index.json').write_text(json.dumps(manifest,separators=(',',':'))+'\n')
(HERE/'facade-classification.json').write_text(json.dumps(report,ensure_ascii=False,separators=(',',':'))+'\n')
print(json.dumps({'tiles':len(records),'gzipBytes':sum(r['gzipBytes'] for r in records.values()),'counts':dict(counts)},ensure_ascii=False),flush=True)
