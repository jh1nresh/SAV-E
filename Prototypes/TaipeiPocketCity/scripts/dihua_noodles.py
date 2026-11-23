"""112 號度小月. Shop location: https://noodle1895.com/branch/taipei-dihua-store/
Street references: https://4travel.jp/os_shisetsu/10590475 and
https://zizitabi.com/entry/DoHsiaoYuehDanZaiNoodles-Taipei . Merchandise is illustrative.
"""
import math


def lantern(f, x):
    """Hanging ribbed red lantern with metal end caps."""
    ends = [(2.00, .07), (2.09, .19), (2.30, .27), (2.67, .27), (2.85, .19), (2.93, .07)]
    facets = 12
    for (za, ra), (zb, rb) in zip(ends, ends[1:]):
        for i in range(facets):
            a, b = [math.tau*j/facets for j in (i,i+1)]
            def side(theta,r,z):
                return f.point(x+math.cos(theta)*r, .28+math.sin(theta)*r,z)
            f.quad(side(a,ra,za),side(b,ra,za),side(b,rb,zb),side(a,rb,zb),
                   ['a53d32','c74839','db5441','ce473b'][i%4])
    for z in (1.96,2.93):
        f.slab(x-.105,z,.21,.065,.19,.37,'494442')
    f.slab(x-.018,2.98,.036,.32,.255,.295,'554c47')
    f.slab(x-.025,1.84,.05,.12,.255,.31,'bb9453')


def make_noodles(f):
    w=f.width
    # Rough grey plaster, three tall windows with individual black Juliet rails.
    f.slab(0,3.27,w,4.65,-3.9,.018,'aba69a','a09c90')
    for i in range(3):
        x=.30+i*(w-.46)/3
        fw=(w-.45)/3-.22
        f.face(x,3.55,fw,3.22,.055,'766f64')
        f.face(x+.12,3.65,fw-.24,3.01,.07,'c0b6a3')
        f.face(x+.20,3.75,fw-.4,2.82,.084,'869492')
        f.face(x+fw*.5,3.7,.06,2.94,.105,'6f695f')
        for z in (4.76,5.76,6.34):
            f.face(x+.16,z,fw-.32,.055,.107,'696860')
        for j in range(9):
            f.slab(x+.06+j*(fw-.12)/8,3.6,.032,.85,.14,.22,'454641')
        f.slab(x,4.43,fw,.06,.11,.24,'454641')
        f.slab(x-.06,3.48,fw+.12,.105,.01,.27,'a49a84')
    for z,c in [(7.25,'968d7e'),(7.38,'c6ba9e'),(7.68,'736e65'),(7.83,'b9af97')]:
        f.slab(-.025,z,w+.05,.11,-.10,.19,c)
    # Grey tiled entry and a view through to the stall, leaving the middle aisle clear.
    f.slab(0,-.05,w,.15,-1.60,.48,'9c9388','c9c2b0')
    for i in range(1,9):
        f.slab(i*w/9,.106,.014,.005,-1.60,.48,'a39d91')
    for i in range(4):
        d=-1.4+i*.47
        f.slab(.02,.106,w-.04,.007,d,d+.016,'a39d91')
    f.face(.015,.1,w-.03,3.19,-1.55,'4b4035')
    for x in (.03,w-.32):
        f.slab(x,0,.29,3.37,-1.57,-1.22,'928a79')
        f.slab(x,0,.29,3.37,-.23,.08,'9f9a8e')
    f.slab(0,3.18,w,.14,-1.57,.13,'c0ac8f')
    f.slab(-.04,3.29,w+.08,.16,-.09,.58,'484849','665e54')
    f.slab(.42,.15,w*.39,.74,-1.48,-.70,'8a6246','c3a476')
    for j in range(4):
        f.face(.47,.21+j*.14,w*.36,.029,-.68,'654936')
    for j in range(3):
        f.slab(.56+j*.45,.89,.26,.12,-1.30,-.94,'423e38','b7a68c')
    for x in (w*.59,w*.82):
        f.slab(x-.18,.36,.36,.10,-.89,-.54,'aa744b','d6af72')
        for edge in (x-.14,x+.09):
            f.slab(edge,.07,.055,.29,-.85,-.78,'986a49')
            f.slab(edge,.07,.055,.29,-.60,-.53,'986a49')
    # Amber leaded-glass transom above the kitchen.
    sx=.46; sw=w*.61; z=2.12
    f.slab(sx,z,sw,.75,-.36,-.30,'604d38')
    f.face(sx+.055,z+.05,sw-.11,.65,-.275,'e9ad57')
    for i in range(7):
        u=sx+.08+i*(sw-.40)/7
        flip=i%2
        pts=[(u,z+.06+flip*.54),(u+.025,z+.06+flip*.54),(u+.33,z+.60-flip*.54),(u+.305,z+.60-flip*.54)]
        f.quad(*(f.point(x,-.26,y) for x,y in pts),'715039')
    f.face(sx+sw*.36,z+.09,sw*.28,.53,-.25,'ac4831')
    f.sign('度小月',sx+sw*.37,z+.21,sw*.26,.28,-.23,'ffe3a1')
    for x in (.68,w-.67):
        lantern(f,x)
    # Projecting bilingual-style blade seen from both directions along the lane.
    f.slab(.10,4.63,.075,.07,.04,.76,'524a42')
    f.slab(.085,3.63,.10,1.0,.51,.79,'d8cbb3')
