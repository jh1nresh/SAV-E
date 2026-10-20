from PIL import Image, ImageFilter
import numpy as np
P="/workspace/critiques/_packets/2026-10-19-doodle-v1-%s.png"
K=1.25
# name: (mock, display box, kind)  kind: art(keep colors) / ink(recolor in dark) / opaque
C={
"wordmark":("home",(312,40,526,100),"ink"),
"underline":("home",(417,125,494,134),"ink"),
"duck":("home",(354,288,434,344),"art"),
"noodles":("home",(354,347,422,404),"art"),
"coffee":("home",(354,408,422,458),"art"),
"num1":("home",(316,303,345,331),"ink"),
"num2":("home",(316,360,345,388),"ink"),
"num3":("home",(316,417,345,445),"ink"),
"tape":("home",(326,454,692,502),"opaque"),
"tab-home":("home",(300,509,720,566),"ink"),
"pin":("map",(353,155,384,193),"ink"),
"title-beijing":("map",(304,56,450,104),"ink"),
"temple":("map",(326,378,408,434),"art"),
"tab-map":("map",(299,507,722,550),"ink"),
"title-friends":("friends",(308,58,472,108),"ink"),
"invite":("friends",(637,70,722,104),"ink"),
"av-m":("friends",(305,124,377,192),"ink"),
"av-l":("friends",(305,206,377,274),"ink"),
"av-k":("friends",(305,289,377,357),"ink"),
"av-a":("friends",(305,370,377,438),"ink"),
"f-coffee":("friends",(652,136,716,184),"art"),
"f-noodles":("friends",(650,212,718,268),"art"),
"f-lantern":("friends",(656,290,712,350),"art"),
"f-hill":("friends",(638,384,726,428),"art"),
"tab-friends":("friends",(299,507,722,550),"ink"),
"title-passport":("passport",(306,56,500,108),"ink"),
"pp-sub":("passport",(308,110,518,134),"ink"),
"pp-card":("passport",(298,141,722,493),"opaque"),
"tab-passport":("passport",(299,507,722,550),"ink"),
"pp-row1":("passport",(304,150,716,246),"art"),
"pp-row2":("passport",(304,250,716,336),"art"),
"pp-row3":("passport",(304,340,716,428),"art"),
"pp-legend":("passport",(312,436,612,486),"ink"),
"pw-yearly":("paywall",(370,368,410,398),"ink"),
"pw-monthly":("paywall",(372,416,402,448),"ink"),
"pw-x":("paywall",(364,50,384,70),"ink"),
"pw-hero":("paywall",(365,92,655,236),"opaque"),
"pw-bookmark":("paywall",(371,270,389,292),"ink"),
}
def bgcol(im):
    a=np.asarray(im.convert("RGB")).astype(float)
    e=np.concatenate([a[0],a[-1],a[:,0],a[:,-1]]);return np.median(e,0)
def matte(im,bg,lo=10,hi=70):
    a=np.asarray(im.convert("RGB")).astype(float)
    d=np.sqrt(((a-bg)**2).sum(-1))
    al=np.clip((d-lo)/(hi-lo),0,1)
    out=np.where(al[...,None]>0.01,(a-(1-al[...,None])*bg)/np.maximum(al[...,None],.01),a)
    out=np.clip(out,0,255)
    return Image.fromarray(np.dstack([out,al*255]).astype(np.uint8),"RGBA")
def darkink(im):
    a=np.asarray(im).astype(float);rgb=a[...,:3]/255
    mx=rgb.max(-1);mn=rgb.min(-1);sat=(mx-mn)/np.maximum(mx,1e-3)
    r,g,b=rgb[...,0],rgb[...,1],rgb[...,2]
    green=(g>r+.05)&(g>=b-.02)&(mx<.6)
    neutral=(sat<.3)&(mx<.75)&~green
    o=a.copy()
    o[neutral,:3]=[244,241,228]; o[green,:3]=[185,224,201]
    return Image.fromarray(o.astype(np.uint8),"RGBA")
mocks={}
for n,(m,b,k) in C.items():
    im=mocks.setdefault(m,Image.open(P%m).convert("RGB")).crop(tuple(int(v*K) for v in b))
    up=im.resize((im.width*3,im.height*3),Image.LANCZOS).filter(ImageFilter.UnsharpMask(2,80,2))
    if k=="opaque": up.save(f"assets/{n}.png"); 
    else:
        mm=matte(up,bgcol(im)); mm.save(f"assets/{n}.png")
        if k=="ink": darkink(mm).save(f"assets/{n}-dark.png")
    print(n,up.size)
