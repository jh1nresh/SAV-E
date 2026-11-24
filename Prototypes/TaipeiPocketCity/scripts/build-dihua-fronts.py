"""Build illustrated Dihua street façades in survey-local metres, relative to the visible street."""
import gzip
import json
import math
import struct
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from dihua_noodles import make_noodles
from dihua_north import make_north

DATA = Path(__file__).resolve().parents[1] / 'data' / 'city-streets'
ORIGIN = (121.509945, 25.056445)
# South to north; the mapped shell can combine shop houses. Bay divisions are illustrative.
# 85 and 87: https://tcmb.culture.tw/zh-tw/detail?id=20060217000002&indexCode=BOCH_CountryCulture_12
# https://tcmb.culture.tw/zh-tw/detail?id=20220711000001&indexCode=BOCH_CountryCulture_12
# 87: https://commons.wikimedia.org/wiki/File:迪化街一段87號_182953.jpg
# 89: https://www.soho.com.tw/cht/index.php?article_id=495&code=list&flag=detail&ids=35
# The north edge of 89 is estimated within the shared 89–91 survey shell.
EDGES = [-9.553, -3.942, 1.355, 6.430, 11.505, 17.639, 22.484, 27.974]
mesh = bytearray()
cream, stone, ink = 'e9d7b7', 'bcafa0', '504642'

def quad(a,b,c,d,color):
    rgb = int(color,16)+2
    for pt in (a,b,c,a,c,d):
        mesh.extend(struct.pack('<6f',*pt,0,1,rgb))

class Front:
    quad = staticmethod(quad)
    def __init__(self, start, end, ground):
        self.end, self.width, self.ground = end, (end-start)*1.00529, ground

    def point(self,u,d,z):
        # Seen from the street, left is north and positive depth faces west.
        y = self.end-u/1.00529
        # Follow the DEM across each threshold; the floor otherwise cuts into the sloped walk.
        ground=self.ground+(self.width*.5-u)*-.027
        return (-1.454-.10296*y-d*.99474, y-d*.10242, ground+z)

    def face(self,x,y,w,h,d,c):
        quad(*(self.point(u,d,z) for u,z in [(x,y),(x+w,y),(x+w,y+h),(x,y+h)]),c)

    def slab(self,x,y,w,h,back,front,c,top=None):
        self.face(x,y,w,h,front,c)
        self.face(x,y,w,h,back,c)
        for u in (x,x+w):
            quad(*(self.point(u,d,z) for d,z in [(back,y),(front,y),(front,y+h),(back,y+h)]),c)
        for z in (y,y+h):
            quad(*(self.point(u,d,z) for u,d in [(x,back),(x+w,back),(x+w,front),(x,front)]),top or c)

    def sign(self,text,x,z,width,height,depth,color):
        font=ImageFont.truetype('/System/Library/Fonts/STHeiti Medium.ttc',25)
        box=font.getbbox(text)
        mask=Image.new('1',(box[2]-box[0],box[3]-box[1]))
        ImageDraw.Draw(mask).text((-box[0],-box[1]),text,font=font,fill=1)
        for row in range(mask.height):
            begin=None
            for col in range(mask.width+1):
                lit=col<mask.width and mask.getpixel((col,row))
                if lit and begin is None: begin=col
                if not lit and begin is not None:
                    self.face(x+begin/mask.width*width,z+(mask.height-row-1)/mask.height*height,
                              (col-begin)/mask.width*width,height/mask.height,depth,color)
                    begin=None

    def window(self,x,z,w,h):
        self.face(x-.08,z-.09,w+.16,h+.18,.075,'b3a08a')
        self.face(x,z,w,h,.091,ink)
        self.face(x+.08,z+.07,w-.16,h-.15,.10,'728e86')
        self.face(x+.10,z+.12,w*.28,h-.24,.106,'93b0a3')
        self.face(x+w*.47,z+.05,.055,h-.1,.12,'574c3d')
        self.face(x+.04,z+h*.67,w-.08,.06,.12,'655746')
        self.slab(x-.12,z-.13,w+.24,.12,.02,.21,cream)
        for fraction in (.28,.52):
            self.face(x+.06,z+h*fraction,w-.12,.04,.116,'c0af96')
    def make(self,kind):
        w=self.width
        eave=[7.8,8.35,7.32][kind]
        wall=['b19e79','cdc5ae','b27964'][kind]
        floor=3.32
        # Section of street roof behind the parapet; close all visible faces back to the survey roof.
        self.slab(.01,4.50,w-.02,eave-4.50,-5.0,.025,wall,'afa394')
        self.face(0,floor,w,eave-floor,.045,wall)
        # Visible masonry joints picked out in fine, low-contrast ink.
        for row in range(int((eave-floor)/.19)):
            z=floor+row*.19
            self.face(.02,z,w-.04,.016,.049,['a08e72','b6ae9d','a56e59'][kind])
            for i in range(1,int(w/.44)):
                self.face(i*.44+(row%2)*.21,z,.014,.18,.050,'b69a84')
        self.slab(0,eave-.26,w,.14,-.10,.17,stone)
        self.slab(-.025,eave-.09,w+.05,.11,-.12,.24,cream)
        if kind==2:
            for inset,level in ((.84,.20),(1.16,.37)):
                self.slab(inset,eave-.05,w-2*inset,level,-.20,.12,'d4c0a9')
                self.slab(inset-.06,eave+level-.08,w-2*inset+.12,.08,-.24,.19,cream)
        for seam in range(1,9):
            d=-.30-seam*.49
            self.slab(.08,eave+.007,w-.16,.012,d-.013,d+.013,'a99f90')
        for i in range(3):
            self.window((i+.20)*w/3,floor+.67,w/3*.60,eave-floor-1.60)
        if kind==1:
            for i in range(11):
                u=.17+i*(w-.34)/11
                self.face(u,eave-.38,.14,.10,.15,'806f5e')
            self.face(.08,3.1,w-.16,.99,.14,'727f79')
            self.slab(w*.25,3.27,w*.50,.59,.14,.22,'806764','a98d83')
            self.sign('行藥成德',w*.28,3.40,w*.44,.30,.23,'e0c1a2')
            for i in range(3):
                x=(i+.16)*w/3
                for j in range(7): self.face(x+.13+j*.13,4.07,.032,.57,.17,'726658')
                self.slab(x+.08,4.61,w*.235,.055,.05,.23,'ab9272')
            # Wood shutters below the original historic sign and a terracotta arcade floor.
            self.face(.29,.07,w-.58,2.88,-1.31,'815736')
            for j in range(6):
                x=.34+j*(w-.7)/6
                self.face(x,.12,(w-.79)/6-.05,1.83,-1.28,'6e4933' if j%2 else '96653d')
                self.face(x+.06,1.96,(w-.79)/6-.18,.70,-1.27,'635244')
            for i in range(5):
                u=.38+i*(w-.75)/5
                self.face(u,.35,.49,1.22,-1.25,'785039')
                self.face(u+.045,.39,.40,1.14,-1.23,'8b5b3e')
            self.face(w*.65,.08,w*.14,2.62,-1.22,'443c32')
        if kind==2:
            self.face(.20,4.0,w-.40,2.25,.13,'576652')
            self.slab(.12,6.20,w-.24,.16,.12,.47,'7a9e7e')
            for i in range(12):
                self.face(.21+i*(w-.42)/11,4.02,.036,2.18,.18,'d5d2ae')
            for i in range(8): self.face(.20,4.02+i*.28,w-.40,.035,.19,'d5d2ae')
        for i in range(4):
            x=max(0,min(w-.15,i*w/3-.075))
            self.slab(x,floor+.20,.15,eave-floor-.47,-.02,.115,stone if kind!=2 else '9e6659')
        self.slab(0,floor-.10,w,.27,-1.40,.21,'ccbaa2',cream)
        # The passage contains a recessed back wall, paved floor, soffit and structural piers.
        self.slab(0,-.055,w,.15,-1.42,.48,'b5a18b','af7154' if kind==1 else 'c8b6a1')
        for i in range(1,int(w/.55)):
            self.slab(i*.55,.098,.014,.004,-1.42,.48,'a99785')
        for row in range(1,5):
            d=.47-.39*row
            self.slab(.02,.099,w-.04,.005,d,d+.013,'bfa385' if kind!=1 else 'c09573')
        self.slab(0,3.14,w,.12,-1.46,.13,'9c8975')
        self.face(0,0,w,3.15,-1.40,'584a41')
        for x in (0,w-.28):
            self.slab(x,0,.28,3.17,-1.42,-1.14,'9b8471')
            self.slab(x,0,.28,3.17,-.22,.07,wall)
            self.slab(x-.018,-.04,.316,.68,-.25,.10,'a39988')
            self.slab(x-.035,2.85,.35,.22,-.26,.12,cream)
        # Leave an open passage between the threshold and each counter.
        opening=[.57,.51,.19][kind]*w
        self.face(opening-.49,.02,.98,2.28,-1.36,'403c37')
        self.face(opening-.50,.04,.065,2.20,-1.33,'b18a5e')
        self.slab(opening-.51,.025,1.02,.055,-1.45,-1.02,'d4c4aa')
        for i in range(0 if kind==1 else 12):
            x=.36+i*(w-.70)/12
            if abs(x-opening)<.70: continue
            for j in range(3):
                self.face(x,.62+j*.34,.22,.25,-1.32,
                          ['b9895c','836648','c99d60','a46149'][(i+2*j+kind)%4])
            self.face(x,1.58,.20,.26,-1.32,'c2ad84')
        counterX=.43 if kind!=2 else w*.53
        if kind!=1: self.slab(counterX,.16,w*.37,.81,-1.22,-.34,['a88760','735846','bd8c50'][kind],'ddbd8d')
        for j in range(0 if kind==1 else 4):
            self.slab(counterX+.08+j*w*.084,.97,.27,.15,-.85,-.42,'ba925b','d9b578')
        if kind==2:
            for j in range(4):
                for i in range(3):
                    x=counterX+.10+j*w*.084+i*.058
                    self.slab(x,1.13,.083,.08,-.73,-.51,'aa7344','d6a55d')
            self.slab(counterX+.1,1.10,w*.32,.06,-.86,-.39,'dbd0b1')
            self.face(counterX+.13,.27,w*.29,.42,-.32,'4e6c59')
            self.sign('爵林',counterX+.29,.36,.58,.24,-.30,'e7d5ae')
            self.face(.34,2.12,w-.68,.68,-.16,'c5ac82')
            self.sign('JUELIN NUTS',w*.27,2.39,w*.47,.21,-.14,'403d38')
            self.sign('爵林堅果',w*.40,2.20,w*.21,.13,-.14,'514536')
            # Narrow blue-white striped apron and a sloping retractable canvas.
            # A planted pot at the outer brick pier, visible in the city's frontage photograph.
            self.slab(.36,0,.34,.42,-.41,-.03,'a49679','796b51')
            for i,(u,z,h) in enumerate(((.33,.38,.38),(.51,.38,.57),(.62,.38,.30))):
                self.slab(u,z,.13,h,-.32,-.18,['6f8156','889255','63794f'][i])
            for i in range(18):
                a,b=.20+i*(w-.40)/18,.20+(i+1)*(w-.40)/18
                c=['e7dcc3','758990','cfb6a4'][i%3]
                quad(self.point(a,.07,3.29),self.point(b,.07,3.29),
                     self.point(b,.88,2.99),self.point(a,.88,2.99),c)
                self.face(a,2.86,b-a,.13,.88,c)
        elif kind==1:
            self.slab(.30,2.92,w-.6,.15,-.05,.30,'8c7560')
        else:
            self.face(.34,2.38,w-.68,.51,-1.34,'758675')
            for i in range(6): self.face(.35+i*(w-.68)/6,2.41,.04,.46,-1.31,'b4ad92')

class WestFront(Front):
    """Opposite bank: local right runs north and the outward normal points east."""
    def point(self,u,d,z):
        y=self.end-self.width/1.00529+u/1.00529
        ground=self.ground-(u-self.width*.5)*.022
        return (-9.469-.0997*y+d*.995, y+d*.0992, ground+z)


def entrance(front, number):
    # The selectable area follows the ground-floor opening and its two jambs.
    corners = [front.point(u, .115, z) for u, z in
               [(0, .05), (front.width, .05), (front.width, 3.25), (0, 3.25)]]
    return dict(number=number, corners=corners)


def main():
    entrances=[]
    grounds=[6.928,6.789,6.643,6.474,6.278,6.070,5.862]
    for idx,(start,end,ground) in enumerate(zip(EDGES[:-1],EDGES[1:],grounds,strict=True)):
        front=Front(start,end,ground)
        entrances.append(entrance(front,85+2*idx))
        if idx<3:
            front.make(idx)
        else:
            make_north(front,85+2*idx)
    west=WestFront(-4.924,.227,6.709)
    make_noodles(west)
    entrances.append(entrance(west,112))
    lat=math.radians(ORIGIN[1])
    out=DATA/'landmark'/'dihua-fronts.bin.gz'
    out.write_bytes(gzip.compress(mesh,mtime=0))
    info=dict(id='dihua-fronts',entrances=entrances,mx=(180+ORIGIN[0])/360,my=(1-math.asinh(math.tan(lat))/math.pi)/2,
              m=1/(40075016.68557849*math.cos(lat)),verts=len(mesh)//24,box=[121.50979,25.05629,121.51004,25.05672])
    (DATA/'dihua-fronts.json').write_text(json.dumps(info,separators=(',',':'))+'\n')
if __name__=='__main__':
    main()
