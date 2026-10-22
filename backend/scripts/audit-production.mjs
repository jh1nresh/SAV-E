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
const transientPattern =
  /503|502|504|500|429|ENOAUDIT|ECONNRESET|ETIMEDOUT|ENOTFOUND|EAI_AGAIN|ECONNREFUSED|Service Unavailable|Bad Gateway|Gateway Timeout|audit endpoint returned an error|socket hang up|network socket|fetch failed/i;
const findingPattern =
  /found \d+ (?:high|critical) severity|npm audit found production vulnerabilities/i;
const NETWORK_TIMEOUT_MARKER = "npm audit timed out talking to the registry";

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function blobOf({ stdout = "", stderr = "", errorCode = "" }) {
  return `${stdout}\n${stderr}\n${errorCode}`;
}

function hasVulnerabilityFinding(result) {
  return findingPattern.test(blobOf(result));
}

function isTransient(result) {
  if (hasVulnerabilityFinding(result)) return false;
  if (result.timedOut) return true;
  if (result.errorCode && networkCodes.has(result.errorCode)) return true;
  return transientPattern.test(blobOf(result));
}

function runAudit() {
  return new Promise((resolve) => {
    const child = spawn("npm", ["audit", "--omit=dev", "--audit-level=high"], {
      stdio: ["ignore", "pipe", "pipe"],
    });
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
  if (hasVulnerabilityFinding(result)) {
    return `npm audit found production vulnerabilities (attempt ${attempt}/${maxAttempts})`;
  }
  if (result.timedOut || networkCodes.has(result.errorCode) || isTransient(result)) {
    const detail = result.errorCode || (result.timedOut ? `timeout ${timeoutMs}ms` : `exit ${result.code}`);
    return `${NETWORK_TIMEOUT_MARKER} (${detail}, attempt ${attempt}/${maxAttempts})`;
  }
  return `npm audit failed (exit ${result.code}, attempt ${attempt}/${maxAttempts})`;
}

async function runWithRetries(runOnce, { wait = sleep } = {}) {
  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const result = await runOnce(attempt);
    if (result.code === 0 && !result.timedOut && !result.errorCode) {
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

function selfTest() {
  const cases = [
    ["npm warn audit 503 Service Unavailable", true],
    ["{ error: 'Service Unavailable' }", true],
    ["npm error audit endpoint returned an error", true],
    ["npm error code ENOAUDIT", true],
    ["npm error code ETIMEDOUT", true],
    ["npm error code ECONNRESET", true],
    ["npm error code EAI_AGAIN", true],
    ["npm error 500 Internal Server Error", true],
    ["npm error 502 Bad Gateway", true],
    ["npm error 504 Gateway Timeout", true],
    ["found 2 high severity vulnerabilities", false],
    ["found 1 critical severity vulnerability", false],
    ["", false],
  ];

  for (const [text, expected] of cases) {
    const actual = isTransient({ timedOut: false, stdout: text, stderr: "", errorCode: "" });
    if (actual !== expected) {
      throw new Error(`self-test failed for ${JSON.stringify(text)}: got ${actual}`);
    }
  }

  if (!isTransient({ timedOut: true, stdout: "", stderr: "", errorCode: "" })) {
    throw new Error("self-test failed: timeout should be transient");
  }

  for (const code of ["ETIMEDOUT", "ECONNRESET", "EAI_AGAIN"]) {
    if (!isTransient({ timedOut: false, stdout: "", stderr: "", errorCode: code })) {
      throw new Error(`self-test failed: ${code} should be transient`);
    }
  }

  if (
    isTransient({
      timedOut: true,
      stdout: "found 2 high severity vulnerabilities",
      stderr: "",
      errorCode: "ETIMEDOUT",
    })
  ) {
    throw new Error("self-test failed: vulnerability findings must not be treated as transient");
  }

  if (
    !failMessage({ timedOut: true, stdout: "", stderr: "", errorCode: "", code: 1 }, 3).includes(
      NETWORK_TIMEOUT_MARKER,
    )
  ) {
    throw new Error("self-test failed: exhausted timeout must print the network-timeout marker");
  }

  if (
    !failMessage(
      { timedOut: false, stdout: "found 2 high severity vulnerabilities", stderr: "", errorCode: "", code: 1 },
      1,
    ).includes("production vulnerabilities")
  ) {
    throw new Error("self-test failed: findings must fail as vulnerabilities, not a timeout");
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
      return { code: 0, timedOut: false, stdout: "found 0 vulnerabilities", stderr: "", errorCode: "" };
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
        stdout: "found 2 high severity vulnerabilities",
        stderr: "",
        errorCode: "",
      };
    },
    { wait: async () => {} },
  );
  if (findings !== 1 || attempts !== 1) {
    throw new Error(`self-test failed: findings should fail immediately (exit ${findings}, attempts ${attempts})`);
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
