"""Supplement named storefronts with the Taipei Office of Commerce's geocoded shop roster."""
from difflib import SequenceMatcher
import csv
import gzip
import hashlib
import json
import math
import re
import sys
import unicodedata
from collections import Counter
from pathlib import Path
from urllib.request import urlopen
from shapely.geometry import Point, shape

DATA = Path(__file__).resolve().parents[1] / 'data'
PAGE = 'https://data.taipei/dataset/detail?id=0d09e03e-bb11-4213-a9c8-6bfd392fbb16'
CSV = 'https://data.taipei/api/frontstage/tpeod/dataset/resource.download?rid=af4a3527-e6c6-4c43-a127-6f1f4c893582'

def normalize(text):
    s = unicodedata.normalize('NFKC', text).casefold().replace('臺', '台').replace('蔘','參')
    return re.sub(r'[^\w]', '', s).replace('_', '')

def distance(a,b):
    return math.hypot((a[0]-b[0])*100850,(a[1]-b[1])*110800)

def house_number(address):
    text=unicodedata.normalize('NFKC',address).replace(' ', '').replace('之','-')
    # Prefer the number explicitly marked 號 to lane or section numbers.
    m=re.search(r'(\d+(?:-\d+)?)號(?:-(\d+))?',text)
    if not m:return None
    return m[1]+('-'+m[2] if m[2] else '')

def build(raw):
    districts = [(f['properties']['name'],shape(f['geometry'])) for f in json.loads((DATA/'districts.geojson').read_bytes())['features']]
    existing = []
    for path in (DATA/'city170').glob('p*.json.gz'):
        for f in json.load(gzip.open(path))['features']['features']:
            p = f['properties']
            if p['kind']=='poi' and p.get('name'):
                existing.append((normalize(p['name']),f['geometry']['coordinates'],f['id'],p.get('detail','')))
    features, matches, counts, seen = [], {}, Counter(), set()
    for r in csv.DictReader(raw.decode('utf-8-sig').splitlines()):
        name, address = r['店家'].strip(), r['地址'].strip()
        try: coords = [float(r['Longitude']),float(r['Latitude'])]
        except ValueError:
            counts['missingCoordinates']+=1
            continue
        unit = next((n for n,g in districts if g.covers(Point(coords))),None)
        if not unit or any(n in address and n!=unit for n,_ in districts) or not name or not address:
            counts['unconfirmedLocation']+=1
            continue
        canonical = normalize(name)
        identity = canonical,normalize(address)
        if identity in seen:
            counts['duplicateRosterRow']+=1
            continue
        seen.add(identity)
        near = [(d,n,osm,old) for n,pt,osm,old in existing if (d:=distance(coords,pt))<=100]
        same = [(d,osm,old) for d,n,osm,old in near if n==canonical or ((d<40 or (house_number(address) and house_number(address)==house_number(old))) and min(len(n),len(canonical))>=3 and (n in canonical or canonical in n))]
        if same:
            d,osm,old=min(same)
            old_number,new_number=house_number(old),house_number(address)
            if old_number and new_number and old_number!=new_number:
                counts['addressConflict']+=1
                continue
            matches[osm]={'name':name}
            counts['linkedRows']+=1
            continue
        # Withhold likely aliases lacking a confirming address rather than add a second sign.
        if any(d<12 and min(len(n),len(canonical))>=4 and SequenceMatcher(None,n,canonical).ratio()>=.75 for d,n,_,_ in near):
            counts['unresolvedAlias']+=1
            continue
        features.append({'type':'Feature','id':'commerce/'+r['項次'],'geometry':{'type':'Point','coordinates':coords},
                         'properties':{'kind':'poi','category':'commerce_store','categoryLabel':'餐飲店家' if r['類別']=='美食' else '特色店家',
                                       'name':name,'detail':address,'rank':0,'url':PAGE,'source':'臺北市商業處'}})
    return {'features':features,'matches':matches,'audit':dict(counts,added=len(features),matchedPlaces=len(matches)),
            'source':CSV,'sha256':hashlib.sha256(raw).hexdigest()}

if __name__=='__main__':
    raw=Path(sys.argv[1]).read_bytes() if len(sys.argv)>1 else urlopen(CSV,timeout=40).read()
    result=build(raw)
    (DATA/'city170-shops.json.gz').write_bytes(gzip.compress(json.dumps(result,ensure_ascii=False,separators=(',',':')).encode(),mtime=0))
    print(result['audit'])
