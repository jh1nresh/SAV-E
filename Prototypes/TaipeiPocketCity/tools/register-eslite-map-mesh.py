"""Register the accepted Pocket City Eslite mesh with the city's LOD1 survey."""
import argparse
import bisect
import gzip
import json
import math
import struct
from pathlib import Path

# Each surveyed boundary matches the next receding outline in the Pocket City export.
ART_HEIGHTS = (0, 3.2, 6.4, 9.6, 12.8, 16.0, 19.2, 22.4, 28.8, 32.0, 35.2, 38.4, 41.6, 44.8)
SURVEY_HEIGHTS = (0, 6.43008, 12.27015, 17.13022, 21.30025, 25.31013, 29.39025, 33.55969,
                  41.89975, 46.06978, 49.97010, 54.28005, 58.77991, 69.50983)
GROUND = 7.01002
NAME = "誠品生活松菸"

def calibrated_height(z):
    i = min(len(ART_HEIGHTS)-2, max(0, bisect.bisect_right(ART_HEIGHTS, z)-1))
    fraction = (z-ART_HEIGHTS[i])/(ART_HEIGHTS[i+1]-ART_HEIGHTS[i])
    return GROUND + SURVEY_HEIGHTS[i] + fraction * (SURVEY_HEIGHTS[i+1]-SURVEY_HEIGHTS[i])

def mercator(lng, lat):
    return (lng+180)/360, (1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2

def register(export_dir,scene_path):
    parts=json.loads((export_dir/'map-mesh.json').read_text())['parts']
    part=next(row for row in parts if row['name']==NAME)
    scene=json.loads(scene_path.read_text())['meta']
    origin_lng,origin_lat=scene['lon'],scene['lat']
    cosine,sine=math.cos(math.radians(scene['rotation'])),math.sin(math.radians(scene['rotation']))
    degree_east,degree_north=111320*math.cos(math.radians(origin_lat)),110574

    def geographic(x,y):
        return origin_lng+(x*cosine-y*sine)/degree_east,origin_lat+(x*sine+y*cosine)/degree_north

    center=geographic(*part['at'])
    mx,my=mercator(*center)
    metres=1/(40075016.68557849*math.cos(math.radians(center[1])))
    data=(export_dir/'map-mesh.bin').read_bytes()
    start,end=part['first']*16,(part['first']+part['count'])*16
    payload=bytearray()
    west=south=math.inf
    east=north=-math.inf
    assert len(data[start:end])==part['count']*16 and part['count']%3==0
    for x,y,z,r,g,b,alpha in struct.iter_unpack('<3f4B', data[start:end]):
        assert alpha==255 and math.isfinite(x+y+z) and -.003<=z<=ART_HEIGHTS[-1]+.003
        lon,lat=geographic(x,y)
        west,south=min(west,lon),min(south,lat)
        east,north=max(east,lon),max(north,lat)
        px,py=mercator(lon,lat)
        tint=(r<<16)+(g<<8)+b+2
        payload+=struct.pack('<6f',(px-mx)/metres,(my-py)/metres,calibrated_height(z),GROUND,SURVEY_HEIGHTS[-1],tint)
    mesh={'id':'taipei-eslite-songyan','name':NAME,'center':center,'mx':mx,'my':my,'m':metres,
          'box':[west,south,east,north], 'verts':part['count'], 'ground':GROUND}
    return mesh,payload

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('export',type=Path,help='Accepted kit export containing its map mesh and scene metadata')
    parser.add_argument('scene',type=Path,help='The authored scene JSON with the original kit projection')
    parser.add_argument('output',type=Path)
    args=parser.parse_args()
    meta,data=register(args.export,args.scene)
    stem=args.output/meta['id']
    args.output.mkdir(parents=True,exist_ok=True)
    stem.with_suffix('.bin.gz').write_bytes(gzip.compress(data,mtime=0))
    stem.with_suffix('.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(meta,ensure_ascii=False))
