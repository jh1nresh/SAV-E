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

await main();
