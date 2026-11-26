"""Recover vertical placement tags lost by the original street and sports atlas.

Usage: python build-city170-grade.py taipei.json.gz /path/to/data city170-grade-ids.js
"""
import argparse
from collections import defaultdict
import gzip
import hashlib
import json
from pathlib import Path


def above_or_below_ground(tags):
    for k in ('layer','level'):
        for value in tags.get(k,'0').split(';'):
            try:
                if float(value.strip())!=0:
                    return True
            except ValueError:
                # Ground placement cannot be proved for a named floor or range.
                return True
    if tags.get('location') in ('roof','rooftop','indoor','indoors','underground','underwater','overground','overhead','elevated'):
        return True
    return any(tags.get(k,'no') not in ('0','no','false') for k in ('bridge','tunnel','indoor','covered'))


def build(source,data):
    import ijson
    expected=json.loads((data/'city170/index.json').read_bytes())['source']['provenance']['taipeiExtractUncompressedSHA256']
    with gzip.open(source,'rb') as stream:
        if hashlib.file_digest(stream,'sha256').hexdigest()!=expected:raise ValueError('Wrong Taipei OSM snapshot')
    features=defaultdict(list)
    for path in (data/'city170').glob('p*.json.gz'):
        for f in json.loads(gzip.decompress(path.read_bytes()))['features']['features']:
            if f['properties']['kind'] in ('walk','road','pitch'):
                kind,osm_type,num=f['id'].split('/')
                features[(osm_type,int(num))].append((kind,f['properties']))
    excluded=defaultdict(list)
    with gzip.open(source,'rb') as stream:
        for row in ijson.items(stream,'elements.item',use_float=True):
            for kind,old in features.get((row['type'],row['id']),[]):
                tags=row.get('tags',{})
                # Existing street filters already use layer, bridge, tunnel and indoor. For
                # these ways only the missing placement tags need a supplemental entry.
                if kind in ('road','walk') and (old.get('layer','0')!='0' or any(old.get(k,'no')!='no' for k in ('bridge','tunnel','indoor'))):
                    continue
                if above_or_below_ground(tags):
                    excluded[kind+'/'+row['type']].append(row['id'])
    return {kind:sorted(ids) for kind,ids in sorted(excluded.items())}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    for arg in ('source','data','output'):parser.add_argument(arg,type=Path)
    args=parser.parse_args()
    ids=build(args.source,args.data);args.output.write_text(
        '// Generated from the public Taipei OSM snapshot by build-city170-grade.py.\nexport default '+
        json.dumps(ids,separators=(',',':'))+';\n')
    print({kind:len(rows) for kind,rows in ids.items()})
