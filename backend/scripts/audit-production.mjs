import { spawn } from "node:child_process";

const maxAttempts = 5;
const timeoutMs = 45_000;
const backoffMs = [2_000, 4_000, 8_000, 16_000];
const transientPattern =
  /503|502|504|429|ENOAUDIT|ECONNRESET|ETIMEDOUT|ENOTFOUND|EAI_AGAIN|Service Unavailable|audit endpoint returned an error|socket hang up|network socket|fetch failed/i;

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isTransient({ timedOut, stdout, stderr }) {
  if (timedOut) return true;
  return transientPattern.test(`${stdout}\n${stderr}`);
}

function runAudit() {
  return new Promise((resolve, reject) => {
    const child = spawn("npm", ["audit", "--omit=dev", "--audit-level=high"], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    let timedOut = false;
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGTERM");
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
      reject(error);
    });
    child.on("close", (code, signal) => {
      clearTimeout(timer);
      resolve({
        code: code ?? 1,
        signal,
        stdout,
        stderr,
        timedOut,
      });
    });
  });
}

function selfTest() {
  const cases = [
    ["npm warn audit 503 Service Unavailable", true],
    ["{ error: 'Service Unavailable' }", true],
    ["npm error audit endpoint returned an error", true],
    ["npm error code ENOAUDIT", true],
    ["found 2 high severity vulnerabilities", false],
    ["", false],
  ];

  for (const [text, expected] of cases) {
    const actual = isTransient({ timedOut: false, stdout: text, stderr: "" });
    if (actual !== expected) {
      throw new Error(`self-test failed for ${JSON.stringify(text)}: got ${actual}`);
    }
  }

  if (!isTransient({ timedOut: true, stdout: "", stderr: "" })) {
    throw new Error("self-test failed: timeout should be transient");
  }

  console.log("audit-production self-test passed");
}

async function main() {
  if (process.argv.includes("--self-test")) {
    selfTest();
    return;
  }

  for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
    const result = await runAudit();
    if (result.code === 0 && !result.timedOut) {
      return;
    }

    if (!isTransient(result) || attempt === maxAttempts) {
      if (result.timedOut) {
        console.error(
          `npm audit timed out after ${timeoutMs}ms (attempt ${attempt}/${maxAttempts})`,
        );
      }
      process.exit(result.timedOut ? 1 : result.code);
    }

    const waitMs = backoffMs[attempt - 1] ?? backoffMs.at(-1);
    const reason = result.timedOut ? `timeout ${timeoutMs}ms` : `exit ${result.code}`;
    console.error(
      `transient npm audit failure (${reason}, attempt ${attempt}/${maxAttempts}); retrying in ${waitMs}ms`,
    );
    await sleep(waitMs);
  }
}

await main();
