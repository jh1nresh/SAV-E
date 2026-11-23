"""Refresh the small viewport index from completed, geographically verified street scenes."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'cities'
PLACES = {
    'tamsui':'新北市', 'keelung':'基隆市', 'taoyuan':'桃園市',
    'hsinchu-city':'新竹市','hsinchu-county':'新竹縣','miaoli':'苗栗縣',
    'taichung':'臺中市','changhua':'彰化縣','nantou':'南投縣','yunlin':'雲林縣',
    'chiayi-city':'嘉義市','chiayi-county':'嘉義縣','tainan':'臺南市','kaohsiung':'高雄市',
    'pingtung':'屏東縣','yilan':'宜蘭縣','hualien':'花蓮縣','taitung':'臺東縣',
    'penghu':'澎湖縣','kinmen':'金門縣','lienchiang':'連江縣',
    'shanghai':'上海','beijing':'北京','los-angeles':'洛杉磯',
}
def verified_landmark_places(folder, meta):
    source = next(folder.glob('osm*.json'))
    data = json.loads(source.read_text())
    refs = {row['type'][0]+str(row['id']): row for row in data['elements']}
    scene = json.loads((folder/'scene.json').read_text())
    result = {}
    for building in scene['buildings']:
        key, name = building['id'], building.get('n')
        if key not in meta['landmarkIds'] or not name:
            continue
        for candidate in (meta.get('placeReferences', {}).get(key), building.get('of'), key):
            row = refs.get(candidate)
            if row and any(row['tags'].get(tag)==name for tag in ('name','name:zh','name:zh-Hant','name:en')):
                result[key] = 'poi/'+row['type']+'/'+str(row['id'])
                break
    return result


def catalog():
    rows = []
    for key, area in PLACES.items():
        folder = ROOT / key
        if not all((folder/f).is_file() for f in ('metadata.json','scene.json','map-mesh.bin','map-mesh.json')):
            continue
        meta = json.loads((folder/'metadata.json').read_text())
        rows.append(dict(id=key,area=area,landmarkPlaceIds=verified_landmark_places(folder,meta),**{k:meta[k] for k in ('name','landmark','center','bounds','sizeMeters','landmarkIds','landmarkSites') if k in meta}))
    return rows
if __name__=='__main__':
    (ROOT/'catalog.json').write_text(json.dumps(catalog(),ensure_ascii=False,indent=2)+'\n')
