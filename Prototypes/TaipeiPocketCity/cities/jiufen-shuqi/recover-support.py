"""Source recapture only: Pillow, Shapely, and the original Songti TC Bold typeface."""
import json
import math
import os
import sys
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from shapely.geometry import LineString, Polygon, mapping
from shapely.ops import unary_union

control = json.load(sys.stdin)
base = Path(__file__).resolve().parent
image = Image.open(base.parent / 'map-tiles/13737-7010.png').convert('RGB')
lon, lat = control['lon'], control['lat']
def ground(x, z):
    lng = lon + x / (111320 * math.cos(math.radians(lat)))
    l = lat - z / 110574
    px = ((lng+180)/360*16384-13737)*256-.5
    py = ((1-math.asinh(math.tan(math.radians(l)))/math.pi)*8192-7010)*256-.5
    ix, iy = math.floor(px), math.floor(py)
    def sample(i, j):
        r, g, b = image.getpixel((i,j))
        return r*256+g+b/256-32768
    return sum(sample(ix+i,iy+j)*(1-abs(px-ix-i))*(1-abs(py-iy-j)) for i in [0,1] for j in [0,1])

# A small fascia/eave margin also avoids slivers from touching source footprints.
plots = [Polygon(r).buffer(0.8,join_style=2) for r in control['polygons']]
walk = LineString([(x,-z) for x,z in control['route']]).buffer(control['width']/2+.15,cap_style=2)
mask=mapping(unary_union(plots+[walk]).simplify(.075,preserve_topology=True))
font=ImageFont.truetype(os.environ.get('SONGTI_FONT','/System/Library/Fonts/Supplemental/Songti.ttc'),37,index=2)
def glyph_rectangles(name):
    im=Image.new('L',(256,66))
    # Preserve the original Songti label / 512 x 132 composition at a 2x downsample.
    ImageDraw.Draw(im).text((128,36),name,fill=255,font=font,anchor='mm')
    rects=[]
    prior={}
    for y in range(im.height):
        active={}
        x=0
        while x<im.width:
            if im.getpixel((x,y))<95:
                x+=1
                continue
            start=x
            while x<im.width and im.getpixel((x,y))>=95:
                x+=1
            key=(start,x)
            if key in prior:
                rects[prior[key]][3]=y+1
                active[key]=prior[key]
            else:
                active[key]=len(rects)
                rects.append([start,y,x,y+1])
        prior=active
    return rects
print(json.dumps({'footprintLocal':mask,'signGlyphs':{n:glyph_rectangles(n) for n in ['昇平戲院','阿妹茶樓']},
    'demAnchorHeight':ground(*control['hero']),'routeDEMHeights':[ground(*p) for p in control['route']]}))
