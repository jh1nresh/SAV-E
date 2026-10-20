import os
OUT="/workspace/critiques/_packets/2026-10-20-doodle-targets"; os.makedirs(OUT,exist_ok=True)
T={"light":dict(paper="#FFF9EB",ink="#2F2E23",forest="#0E4A33",muted="#62594F",coral="#F26B4A",kraft="#EADDC6",kraftL="#F0E3CA",line="#DCCFB9",pencil="#A39C8E",stamp="#C8372D",gold="#B8902F",map="#F2EFE9",road="#FFFFFF",park="#D8E8CF",water="#C9DFEA",block="#E6E1D8"),
   "dark":dict(paper="#1E1C19",ink="#F4F1E4",forest="#B9E0C9",muted="#CFC4B8",coral="#D97861",kraft="#4A3F32",kraftL="#3A332A",line="#4A443B",pencil="#8A8478",stamp="#E0675C",gold="#D9B45A",map="#2B2D31",road="#45474C",park="#2F3D2E",water="#26343F",block="#34363A")}
PLACES=[("天壇公園","Go","0.3 km",True,3),("四季民福烤鴨 天壇店","Eat","0.8 km",True,1),("紅橋市場","Go","1.1 km",False,0),("錦芳小吃 磁器口","Eat","1.4 km",False,0),("北京自然博物館","Go","1.6 km",True,5)]
def css(c,mode):
    grain=("radial-gradient(circle, rgba(47,46,35,.07) 1px, transparent 1.2px) 0 0/16px 16px," if mode=="light" else "")
    return f"""<style>
@font-face{{font-family:Caveat;src:url(file:///usr/share/fonts/truetype/sand-box/google/Caveat/Caveat-VariableFont_wght.ttf)}}
@font-face{{font-family:Iansui;src:url(file:///workspace/dt/Iansui.ttf)}}
*{{box-sizing:border-box;margin:0;padding:0}}
html,body{{width:402px;height:874px;overflow:hidden}}
body{{background:{grain} {c['paper']};color:{c['ink']};font-family:'SF Pro Rounded',Nunito,sans-serif;font-size:17px;position:relative}}
.t{{font-family:Caveat,Iansui;color:{c['forest']}}}
.sb{{position:absolute;top:0;left:0;right:0;height:62px;display:flex;justify-content:space-between;align-items:center;padding:0 32px 0 48px;font:600 17px Nunito;color:{c['ink']}}}
.hi{{position:absolute;bottom:8px;left:134px;width:134px;height:5px;border-radius:3px;background:{c['ink']}}}
.tab{{position:absolute;bottom:0;left:0;right:0;height:84px;border-top:1px solid {c['line']};background:{c['paper']};display:flex;padding:4px 8px 34px}}
.tab div{{flex:1;display:flex;flex-direction:column;align-items:center;gap:2px;font:600 10px Nunito;color:{c['muted']}}}
.tab .on{{color:{c['coral']}}}
.card{{border:1px solid {c['line']};border-radius:12px;background:{c['paper']}}}
.m{{position:absolute;left:24px;right:24px}}
.chip{{height:32px;padding:0 16px;border-radius:16px;border:1px solid {c['line']};display:inline-flex;align-items:center;font:600 15px Nunito}}
.chip.on{{background:{c['coral']};border-color:{c['coral']};color:#fff}}
.row{{height:64px;display:flex;align-items:center;gap:12px;border-bottom:1px dashed {c['line']}}}
.sub{{font-size:13px;color:{c['muted']}}}
</style>"""
def sb(c): return f'<div class="sb"><span>9:41</span><svg width="72" height="14"><g fill="{c["ink"]}"><rect x="0" y="9" width="3" height="5" rx="1"/><rect x="5" y="6" width="3" height="8" rx="1"/><rect x="10" y="3" width="3" height="11" rx="1"/><rect x="15" y="0" width="3" height="14" rx="1"/><rect x="44" y="1" width="24" height="12" rx="3" fill="none" stroke="{c["ink"]}"/><rect x="46" y="3" width="18" height="8" rx="1.5"/></g></svg></div>'
IC={"Home":'<path d="M3 11.5 12 4l9 7.5M6 10v9.5h12V10"/>',"Map":'<path d="M3 6l6-2 6 2 6-2v14l-6 2-6-2-6 2z M9 4v14M15 6v14"/>',"+":'<circle cx="12" cy="12" r="9.5"/><path d="M12 7.5v9M7.5 12h9"/>',"Friends":'<circle cx="9" cy="9" r="3.2"/><circle cx="16.5" cy="10" r="2.6"/><path d="M3.5 19c.8-3.4 3-5 5.5-5s4.7 1.6 5.5 5M14.5 15c2.6-.6 5 .8 6 4"/>',"Passport":'<rect x="5" y="3" width="14" height="18" rx="2"/><circle cx="12" cy="11" r="3.2"/><path d="M9 17h6"/>'}
def tab(c,sel):
    s=""
    for k in IC:
        col=c['coral'] if (k==sel or k=="+") else c['muted']
        s+=f'<div class="{"on" if k==sel else ""}"><svg width="24" height="24" fill="none" stroke="{col}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">{IC[k]}</svg>{"" if k=="+" else k}</div>'
    return f'<div class="tab">{s}</div><div class="hi"></div>'
def mapbg(c,w,h):
    return f'''<svg width="{w}" height="{h}" style="display:block"><rect width="100%" height="100%" fill="{c['map']}"/>
<rect x="{w*.18}" y="{h*.22}" width="{w*.46}" height="{h*.48}" rx="4" fill="{c['park']}"/>
<rect x="{w*.72}" y="{h*.1}" width="{w*.2}" height="{h*.16}" rx="4" fill="{c['block']}"/><rect x="{w*.72}" y="{h*.62}" width="{w*.22}" height="{h*.22}" rx="4" fill="{c['block']}"/>
<path d="M{w*.82} {h} q -20 -{h*.3} 30 -{h*.5}" stroke="{c['water']}" stroke-width="10" fill="none"/>
<g stroke="{c['road']}" fill="none"><path d="M0 {h*.15}H{w}M0 {h*.8}H{w}M{w*.1} 0V{h}M{w*.68} 0V{h}" stroke-width="7"/><path d="M0 {h*.5}H{w*.18}M{w*.64} {h*.45}H{w}M{w*.4} {h*.8}V{h}" stroke-width="4"/></g></svg>'''
def pin(c,x,y,col,n=""):
    return f'<svg style="position:absolute;left:{x-14}px;top:{y-36}px" width="28" height="36"><path d="M14 35C14 35 2 21 2 13a12 12 0 0 1 24 0c0 8-12 22-12 22z" fill="{col}" stroke="#fff" stroke-width="1.5"/><text x="14" y="17.5" text-anchor="middle" font-family="Nunito" font-weight="800" font-size="11" fill="#fff">{n}</text></svg>'
def sticker(c,visited,tier,size=48,kind=0):
    stroke=c['ink'] if visited else c['pencil']; fill=[c['kraft'],"#F7C6A5","#CFE3C4"][kind%3] if visited else "none"
    shapes=['<path d="M8 34l16-20 16 20z M14 34v6h20v-6"/>','<ellipse cx="24" cy="28" rx="15" ry="9"/><path d="M12 24c4-8 20-8 24 0"/>','<rect x="10" y="14" width="28" height="22" rx="3"/><path d="M10 20h28"/>']
    s=f'<svg width="{size}" height="{size}" viewBox="0 0 48 48" fill="{fill}" stroke="{stroke}" stroke-width="1.5" stroke-linejoin="round"'+('' if visited else ' stroke-dasharray="3 2"')+f'>{shapes[kind%3]}'
    if visited:
        col=c['gold'] if tier>=5 else c['stamp']
        s+=f'<g fill="none" stroke="{col}" stroke-width="1.5" transform="rotate(-12 36 36)"><circle cx="36" cy="36" r="9"/>'+(f'<circle cx="36" cy="36" r="6.5"/>' if tier>=3 else '')+f'<text x="36" y="39.5" text-anchor="middle" font-size="9" font-family="Nunito" font-weight="800" fill="{col}" stroke="none">{tier}×</text></g>'
    return s+'</svg>'
def home(c):
    rows="".join(f'<div class="row">{sticker(c,v,t,48,i)}<div style="flex:1"><div style="font-weight:600">{n}</div><div class="sub">{k} · {d}</div></div><svg width="16" height="16" fill="none" stroke="{c["pencil"]}" stroke-width="1.6"><path d="M6 3l5 5-5 5"/></svg></div>' for i,(n,k,d,v,t) in enumerate(PLACES[:4]))
    return f'''<div class="m" style="top:70px;height:44px;display:flex;align-items:center;justify-content:space-between"><span class="t" style="font-size:34px;font-weight:600">Savvy</span><svg width="44" height="44" fill="none" stroke="{c['ink']}" stroke-width="1.6"><circle cx="22" cy="22" r="10"/><circle cx="22" cy="19" r="3.5"/><path d="M15 29c2-4 12-4 14 0"/></svg></div>
<div class="m" style="top:118px;height:32px;display:flex;align-items:center"><span class="t" style="font-size:20px;font-weight:600;border-bottom:2px solid {c['coral']}">Near you · 天壇 Tiantan ▾</span></div>
<div class="m" style="top:158px;display:flex;gap:8px"><span class="chip on">Eat</span><span class="chip">Go</span></div>
<div class="m card" style="top:198px;height:160px;overflow:hidden;position:absolute">{mapbg(c,354,160)}{pin(c,110,80,c['coral'],"1")}{pin(c,200,62,c['coral'],"2")}{pin(c,262,118,c['coral'],"3")}</div>
<div class="m sub" style="top:366px;height:24px;display:flex;align-items:center;font-size:15px">🔍 3 clues waiting nearby</div>
<div class="m" style="top:394px">{rows}</div>
<div class="m" style="top:654px;height:44px;border-radius:12px;background:{c['kraft']};display:flex;align-items:center;justify-content:space-between;padding:0 16px;color:{c['stamp']};font-weight:700;font-size:15px"><span>Collected 7 / 23</span><span>Passport ›</span></div>'''+tab(c,"Home")
def mapscr(c):
    return f'''<div style="position:absolute;inset:0">{mapbg(c,402,874)}</div>{pin(c,120,330,c['coral'],"1")}{pin(c,230,280,c['coral'],"2")}{pin(c,300,420,c['coral'],"3")}{pin(c,180,470,c['stamp'],"✓")}
<div class="m card" style="top:70px;height:48px;display:flex;align-items:center;justify-content:space-between;padding:0 16px"><span class="t" style="font-size:20px;font-weight:600">天壇 Tiantan ▾</span><span style="display:flex;gap:8px"><span class="chip on">Eat</span><span class="chip">Go</span></span></div>
<div class="m card" style="top:590px;height:192px;padding:16px"><div style="display:flex;gap:12px;align-items:center;height:64px">{sticker(c,False,0,48,1)}<div style="flex:1"><div style="font-weight:600">四季民福烤鴨 天壇店</div><div class="sub">Eat · 0.8 km · saved Oct 12</div></div></div>
<div class="sub" style="margin:8px 0 16px">“Book ahead — duck sells out by 19:00.”</div>
<div style="display:flex;gap:8px"><div style="flex:1;height:44px;border-radius:12px;background:{c['coral']};color:#fff;display:flex;align-items:center;justify-content:center;font-weight:700">Directions</div><div style="flex:1;height:44px;border-radius:12px;border:1px solid {c['coral']};color:{c['coral']};display:flex;align-items:center;justify-content:center;font-weight:700">我來過了</div></div></div>'''+tab(c,"Map")
def passport(c):
    cells=""
    data=[("天壇公園",True,3,0),("四季民福",True,1,1),("自然博物館",True,5,2),("紅橋市場",False,0,0),("錦芳小吃",False,0,1),("前門大街",False,0,2)]
    for n,v,t,k in data:
        cells+=f'<div style="height:144px;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px">{sticker(c,v,t,88,k)}<div style="font-size:13px;font-weight:600;color:{c["ink"] if v else c["muted"]}">{n}</div></div>'
    cities="".join(f'<span class="chip{" on" if i==0 else ""}">{x}</span>' for i,x in enumerate(["北京 7/23","上海 2/9","台北 0/4"]))
    return f'''<div class="m" style="top:70px;height:44px;display:flex;align-items:center"><span class="t" style="font-size:34px;font-weight:600">Passport</span></div>
<div class="m sub" style="top:118px;height:24px;font-size:15px">Collected 7 of 36 places</div>
<div class="m" style="top:150px;display:flex;gap:8px">{cities}</div>
<div class="m" style="top:198px;border-radius:12px;background:{c['kraftL']};padding:12px 8px;display:grid;grid-template-columns:repeat(3,1fr);row-gap:8px;height:328px;align-content:center">{cells[:]}</div>
<div class="m" style="top:542px;display:flex;gap:16px;font-size:13px;color:{c['muted']};align-items:center"><span>{sticker(c,True,1,24,0)} 1×</span><span>{sticker(c,True,3,24,0)} 3×</span><span>{sticker(c,True,5,24,0)} 5×</span><span>{sticker(c,False,0,24,0)} saved</span></div>'''+tab(c,"Passport")
def friends(c):
    fr=[("Mia 林","saved 紅橋市場 · 2h","M"),("阿哲","visited 天壇公園 · yesterday","哲"),("Leo","saved 錦芳小吃 · Oct 18","L"),("小雨","3 places in 北京 · Oct 16","雨")]
    rows="".join(f'<div class="row"><div style="width:48px;height:48px;border-radius:24px;border:1px solid {c["line"]};background:{c["kraftL"]};display:flex;align-items:center;justify-content:center;font-weight:700;color:{c["forest"]}">{a}</div><div style="flex:1"><div style="font-weight:600">{n}</div><div class="sub">{s}</div></div></div>' for n,s,a in fr)
    return f'''<div class="m" style="top:70px;height:44px;display:flex;align-items:center;justify-content:space-between"><span class="t" style="font-size:34px;font-weight:600">Friends</span><span class="chip" style="color:{c['coral']};border-color:{c['coral']}">＋ Invite</span></div>
<div class="m t" style="top:126px;font-size:20px;font-weight:600">最近動態 Recent</div>
<div class="m" style="top:158px">{rows}</div>'''+tab(c,"Friends")
def paywall(c):
    return f'''<div style="position:absolute;top:70px;right:24px;width:44px;height:44px;display:flex;align-items:center;justify-content:center"><svg width="20" height="20" stroke="{c['ink']}" stroke-width="1.8"><path d="M4 4l12 12M16 4L4 16"/></svg></div>
<div class="m" style="top:150px;text-align:center"><svg width="120" height="120" viewBox="0 0 48 48" fill="{c['kraft']}" stroke="{c['ink']}" stroke-width="1"><path d="M12 6h24v36l-12-8-12 8z"/><g fill="none" stroke="{c['stamp']}" stroke-width="1.2"><circle cx="24" cy="20" r="7"/><circle cx="24" cy="20" r="5"/></g></svg></div>
<div class="m t" style="top:290px;text-align:center;font-size:34px;font-weight:600">Savvy Pro</div>
<div class="m card" style="top:354px;height:64px;display:flex;align-items:center;gap:12px;padding:0 16px"><svg width="24" height="24" fill="none" stroke="{c['forest']}" stroke-width="2" stroke-linecap="round"><path d="M5 12.5l4.5 4.5L19 7"/></svg><span style="font-weight:600">Unlimited saved places</span></div>
<div class="m sub" style="top:434px;text-align:center;font-size:15px">You've saved 50 places. Keep going.</div>
<div class="m" style="top:594px;height:56px;border-radius:12px;background:{c['coral']};color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;font-weight:700">Continue — ¥38 / year</div>
<div class="m sub" style="top:662px;text-align:center;font-size:11px;line-height:16px">Subscription renews automatically at ¥38/year unless cancelled at least 24 hours before the end of the current period. Payment is charged to your Apple ID. Manage or cancel anytime in Settings › Apple ID › Subscriptions.</div>
<div class="m" style="top:756px;height:44px;display:flex;justify-content:center;gap:24px;font-size:13px;font-weight:600;color:{c['coral']};align-items:center"><span>Restore Purchases</span><span>Terms</span><span>Privacy</span></div><div class="hi"></div>'''
S={"home":home,"map":mapscr,"passport":passport,"friends":friends,"paywall":paywall}
for name,f in S.items():
    for mode,c in T.items():
        open(f"{OUT}/{name}-{mode}.html","w").write(f'<!doctype html><meta charset="utf-8">{css(c,mode)}<body>{f(c)}{sb(c)}</body>')
