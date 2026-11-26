"""Validate generated facade classes against the actual bundled mesh bytes."""
from pathlib import Path
import gzip,hashlib,json
root=Path(__file__).resolve().parent
web=root.parent.parent
r=json.loads((root/'facade-classification.json').read_text())
out=web/'assets/pocket-survey/classes'
manifest=json.loads((out/'index.json').read_text())
assert set(manifest['tiles'])==set(r['tiles'])=={p.name.removesuffix('.bin.gz') for p in out.glob('*.bin.gz')}
for key,row in r['tiles'].items():
    data=gzip.decompress((out/(key+'.bin.gz')).read_bytes())
    mesh=gzip.decompress((web/f'data/200/{key}.bin.gz').read_bytes())
    assert len(data)==row['vertices'] and len(mesh)==len(data)*24,key
    assert hashlib.sha256(data).hexdigest()==row['classSHA256'],key
    assert hashlib.sha256(mesh).hexdigest()==row['meshSHA256'],key
    assert max(data)<=3 and all(data[i]==data[i+1]==data[i+2] for i in range(0,len(data),3)),key
print('PASS:4816 class payloads, source meshes, hashes, counts and triangle labels')
