import os,subprocess
OUT=os.path.dirname(os.path.abspath(__file__)); A=OUT+"/assets"
T={"light":dict(paper="#FFF9EB",ink="#2F2E23",forest="#0E4A33",muted="#5E574C",coral="#E8573A",kraft="#E9DCC3",line="#C9BBA2",pencil="#A39C8E",map="#F2EFE9",road="#FFFFFF",park="#D8E8CF",water="#C9DFEA",block="#E6E1D8",card="#FFFBF1"),
   "dark":dict(paper="#1E1C19",ink="#F4F1E4",forest="#B9E0C9",muted="#CFC4B8",coral="#E06A4F",kraft="#4A3F32",line="#5A5246",pencil="#8A8478",map="#2B2D31",road="#45474C",park="#2F3D2E",water="#26343F",block="#34363A",card="#26231F")}
GRAIN="url(\"data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='160' height='160'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='2' seed='3'/><feColorMatrix values='0 0 0 0 .4 0 0 0 0 .3 0 0 0 0 .2 0 0 0 .09 0'/></filter><rect width='100%' height='100%' filter='url(%23n)'/></svg>\")"
def img(n,mode,**st):
    f=f"{A}/{n}-dark.png" if mode=="dark" and os.path.exists(f"{A}/{n}-dark.png") else f"{A}/{n}.png"
    return f'<img src="file://{f}" style="position:absolute;{";".join(f"{k.replace("_","-")}:{v}px" if isinstance(v,(int,float)) else f"{k.replace("_","-")}:{v}" for k,v in st.items())}">'
def css(c,mode):
    dots=f"radial-gradient(circle, rgba(47,46,35,.16) 1px, transparent 1.3px) 0 0/16px 16px," if mode=="light" else ""
    return f"""<style>
@font-face{{font-family:PH;src:url(file:///workspace/dt/PatrickHand.ttf)}}
@font-face{{font-family:Iansui;src:url(file:///workspace/dt/Iansui.ttf)}}
*{{box-sizing:border-box;margin:0;padding:0}}
html,body{{width:402px;height:874px;overflow:hidden}}
body{{background:{GRAIN},{dots} {c['paper']};color:{c['ink']};font-family:PH,Iansui,sans-serif;font-size:17px;position:relative}}
.a{{position:absolute}} .m{{position:absolute;left:24px;right:24px}}
.sb{{position:absolute;top:0;left:0;right:0;height:56px;display:flex;justify-content:space-between;align-items:center;padding:6px 30px 0 46px;font:600 17px -apple-system,Nunito,sans-serif;color:{c['ink']}}}
.hi{{position:absolute;bottom:8px;left:134px;width:134px;height:5px;border-radius:3px;background:{c['ink']}}}
.pill{{position:absolute;height:34px;border-radius:17px;border:1.5px solid {c['ink']};display:flex;align-items:center;justify-content:center;font-size:20px}}
.pill.on{{background:{c['coral']};border-color:{c['coral']};color:#fff}}
.dash{{border-bottom:1.5px dashed {c['pencil']}}}
.sub{{font-size:16px;color:{c['muted']}}}
.tabbar{{position:absolute;left:0;right:0;top:780px;bottom:0;border-top:1.5px solid {c['line']};background:{c['paper']}}}
</style>"""
def sb(c): return f'<div class="sb"><span>9:41</span><svg width="72" height="14"><g fill="{c["ink"]}"><rect x="0" y="9" width="3" height="5" rx="1"/><rect x="5" y="6" width="3" height="8" rx="1"/><rect x="10" y="3" width="3" height="11" rx="1"/><rect x="15" y="0" width="3" height="14" rx="1"/><rect x="44" y="1" width="24" height="12" rx="3" fill="none" stroke="{c["ink"]}"/><rect x="46" y="3" width="18" height="8" rx="1.5"/></g></svg></div>'
def tab(c,mode,sel): return f'<div class="tabbar"></div>'+img(f"tab-{sel}",mode,left=4,top=786,width=394)+'<div class="hi"></div>'
def mapbg(c,w,h):
    return f'''<svg width="{w}" height="{h}" style="display:block"><rect width="100%" height="100%" fill="{c['map']}"/>
<rect x="{w*.3}" y="{h*.28}" width="{w*.36}" height="{h*.36}" rx="14" fill="{c['park']}"/>
<rect x="{w*.74}" y="{h*.1}" width="{w*.2}" height="{h*.16}" rx="4" fill="{c['block']}"/><rect x="{w*.74}" y="{h*.68}" width="{w*.2}" height="{h*.18}" rx="4" fill="{c['block']}"/><rect x="{w*.05}" y="{h*.62}" width="{w*.16}" height="{h*.2}" rx="4" fill="{c['block']}"/>
<g stroke="{c['road']}" fill="none"><path d="M0 {h*.18}H{w}M0 {h*.76}H{w}M{w*.22} 0V{h}M{w*.7} 0V{h}" stroke-width="7"/><path d="M0 {h*.48}H{w*.3}M{w*.66} {h*.44}H{w}M{w*.45} {h*.76}V{h}M{w*.1} 0L{w*.22} {h*.3}" stroke-width="4"/></g></svg>'''
def pin(c,x,y,n,big=30):
    r=big/2
    return f'<svg class="a" style="left:{x-r-2}px;top:{y-big-10}px" width="{big+4}" height="{big+12}"><path d="M{r+2} {big+10} L{r-4} {big-1} L{r+8} {big-1}Z" fill="{c["coral"]}"/><circle cx="{r+2}" cy="{r+2}" r="{r-0.5}" fill="{c["card"]}" stroke="{c["coral"]}" stroke-width="2.2"/><text x="{r+2}" y="{r+8.5}" text-anchor="middle" font-family="PH" font-size="{big*.62}" fill="{c["coral"]}">{n}</text></svg>'
def wobble(c,w,h,sw=2):
    # hand-drawn irregular rounded rect
    p=f"M14 2.5 C{w*.3} 1, {w*.6} 4, {w-15} 2 Q{w-1.5} 2.5 {w-2} 15 C{w-.5} {h*.35}, {w-3.5} {h*.7}, {w-2.5} {h-14} Q{w-3} {h-2} {w-16} {h-2.5} C{w*.65} {h-.5}, {w*.3} {h-4}, 15 {h-2} Q2.5 {h-2.5} 2.5 {h-15} C1.5 {h*.65}, 4 {h*.3}, 2 15 Q2.5 3 14 2.5Z"
    return f'<svg class="a" style="left:0;top:0" width="{w}" height="{h}"><path d="{p}" fill="none" stroke="{c["ink"]}" stroke-width="{sw}" stroke-linecap="round"/></svg>'
def home(c,mode):
    rows=""
    for i,(st,n,d,sw) in enumerate([("duck","Siji Minfu Roast Duck","Eat · 450m",64),("noodles","Fangzhuanchang Noodles","Eat · 800m",58),("coffee","Grey Cafe","Eat · 1.1km",58)]):
        y=420+i*84
        rows+=img(f"num{i+1}",mode,left=22,top=y+22,width=31)+img(st,mode,left=62+(64-sw)/2,top=y+8,width=sw)+f'<div class="a" style="left:142px;top:{y+12}px;font-size:22px">{n}</div><div class="a sub" style="left:142px;top:{y+40}px">{d}</div>'+(f'<div class="a dash" style="left:24px;right:24px;top:{y+82}px"></div>' if i<2 else "")
    return (img("wordmark",mode,left=18,top=62,height=62)+
      f'<div class="pill on" style="left:250px;top:78px;width:66px">Eat</div><div class="pill" style="left:324px;top:78px;width:62px">Go</div>'
      f'<div class="a" style="left:24px;top:128px;font-size:27px;color:{c["ink"]}">Near you · <span style="color:{c["forest"]}">Tiantan</span></div>'
      +img("underline",mode,left=135,top=162,width=88)+
      f'<div class="a" style="left:24px;top:174px;font-size:18px">2 clues waiting · Review ›</div>'
      f'<div class="m" style="top:210px;height:192px"><div style="position:absolute;inset:3px;border-radius:14px;overflow:hidden">{mapbg(c,348,186)}</div>{wobble(c,354,192)}{pin(c,70,72,1)}{pin(c,40,140,2)}{pin(c,120,170,3)}{pin(c,190,110,4)}{pin(c,290,150,5)}{pin(c,300,60,6)}</div>'
      +rows+img("tape",mode,left=22,top=690,width=358)+tab(c,mode,"home"))
def mapscr(c,mode):
    return (f'<div class="a" style="inset:0">{mapbg(c,402,874)}</div>'
      f'<div class="a" style="left:0;right:0;top:0;height:160px;background:linear-gradient({c["paper"]} 70%,transparent)"></div>'
      +img("title-beijing",mode,left=20,top=60,height=50)+
      ''.join(f'<div class="pill{" on" if k=="Eat" else ""}" style="left:{24+i*76}px;top:116px;width:68px;font-size:18px;{"" if k=="Eat" else "background:"+c["paper"]}">{k}</div>' for i,k in enumerate(["Eat","Go"]))
      +pin(c,110,250,1,34)+pin(c,70,350,2,34)+pin(c,140,440,3,34)+pin(c,210,345,4,34)+pin(c,320,430,5,34)+pin(c,330,240,6,34)+
      f'<div class="a" style="left:16px;right:16px;top:568px;height:196px;background:{c["card"]};border:1.5px solid {c["line"]};border-radius:16px"></div>'
      f'<div class="a" style="left:181px;top:578px;width:40px;height:4px;border-radius:2px;background:{c["line"]}"></div>'
      +img("temple",mode,left=32,top=596,width=92)+
      f'<div class="a" style="left:136px;top:602px;font-size:25px">Temple of Heaven Park</div><div class="a sub" style="left:136px;top:636px">Go · 300m</div>'
      f'<div class="a" style="left:32px;top:690px;width:164px;height:48px;border-radius:10px;background:{c["coral"]};color:#fff;font-size:21px;display:flex;align-items:center;justify-content:center">Directions</div>'
      f'<div class="a" style="left:206px;top:690px;width:164px;height:48px;border-radius:10px;border:1.5px solid {c["ink"]};font-size:21px;display:flex;align-items:center;justify-content:center">I\'ve been here</div>'
      +tab(c,mode,"map"))
def friends(c,mode):
    s=img("title-friends",mode,left=20,top=60,height=56)+img("invite",mode,left=292,top=76,width=90)
    D=[("m","Mia","last at Grey Cafe · 2d","f-coffee",58),("l","Leo","last at Fangzhuanchang Noodles · 5d","f-noodles",58),("k","Kai","last at Temple of Heaven Park · 1w","f-lantern",44),("a","Ana","last at Jingshan Hill · 2w","f-hill",70)]
    for i,(a,n,sub,st,sw) in enumerate(D):
        y=132+i*92
        s+=img(f"av-{a}",mode,left=20,top=y+10,width=72)+f'<div class="a" style="left:104px;top:{y+18}px;font-size:26px">{n}</div><div class="a" style="left:104px;top:{y+52}px;font-size:16px">{sub}</div>'+img(st,mode,left=354-sw/2,top=y+22,width=sw)+(f'<div class="a dash" style="left:24px;right:24px;top:{y+92}px"></div>' if i<3 else "")
    return s+tab(c,mode,"friends")
def passport(c,mode):
    s=img("title-passport",mode,left=20,top=60,height=56)+img("pp-sub",mode,left=24,top=120,width=216)
    s+=f'<div class="a" style="left:16px;right:16px;top:158px;height:496px;background:{c["kraft"]};border:1.5px solid {c["line"]};border-radius:12px"></div>'
    for i in range(3): s+=img(f"pp-row{i+1}",mode,left=26,top=176+i*124,width=350)
    s+=img("pp-legend",mode,left=32,top=566,width=290)
    return s+tab(c,mode,"passport")
def paywall(c,mode):
    plan=lambda y,ic,t,p,best,sel: f'<div class="a" style="left:24px;right:24px;top:{y}px;height:64px;border-radius:12px;border:1.5px solid {c["coral"] if sel else c["line"]};background:{c["card"]}"></div>'+img(ic,mode,left=38,top=y+16,width=40)+f'<div class="a" style="left:92px;top:{y+8}px;font-size:20px;line-height:24px">{t}<br>{p}</div>'+(f'<div class="a" style="right:38px;top:{y+20}px;font-size:15px;color:{c["coral"]};border:1.2px solid {c["coral"]};border-radius:4px;padding:0 6px">Best value</div>' if best else "")
    return (img("pw-x",mode,left=28,top=74,width=18)+img("wordmark",mode,left=118,top=60,height=58)+
      img("pw-hero",mode,left=24,top=132,width=354)+
      f'<div class="a" style="left:24px;top:330px;font-size:29px">Save every place you love</div>'
      +img("pw-bookmark",mode,left=26,top=384,width=18)+f'<div class="a" style="left:56px;top:380px;font-size:21px">Unlimited saved places</div>'
      f'<div class="a sub" style="left:24px;top:420px;font-size:17px">You\'ve saved 50 places. Keep going.</div>'
      +plan(468,"pw-yearly","Yearly","$39.99",True,True)+plan(546,"pw-monthly","Monthly","$6.99",False,False)+
      f'<div class="a" style="left:24px;right:24px;top:636px;height:52px;border-radius:12px;background:{c["coral"]};color:#fff;font-size:23px;display:flex;align-items:center;justify-content:center">Continue</div>'
      f'<div class="a sub" style="left:24px;right:24px;top:698px;font-size:12px;line-height:15px;text-align:center">Renews automatically unless cancelled at least 24 hours before the end of the period. Charged to your Apple ID. Manage or cancel in Settings › Apple ID › Subscriptions.</div>'
      f'<div class="a" style="left:0;right:0;top:770px;height:44px;display:flex;justify-content:center;align-items:center;gap:8px;font-size:16px">Restore · Terms · Privacy</div><div class="hi"></div>')
S={"home":home,"map":mapscr,"passport":passport,"friends":friends,"paywall":paywall}
for name,f in S.items():
    for mode,c in T.items():
        h=f"{OUT}/{name}-{mode}.html"
        open(h,"w").write(f'<!doctype html><meta charset="utf-8">{css(c,mode)}<body>{f(c,mode)}{sb(c)}</body>')
        for sfx,dsf in (("",1),("@3x",3)):
            subprocess.run(["google-chrome","--headless=new","--no-sandbox","--disable-gpu","--hide-scrollbars","--allow-file-access-from-files",f"--force-device-scale-factor={dsf}","--window-size=402,874",f"--screenshot={OUT}/{name}-{mode}{sfx}.png","--virtual-time-budget=2000","file://"+h],capture_output=True)
