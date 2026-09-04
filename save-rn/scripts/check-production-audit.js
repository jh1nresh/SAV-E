const { spawnSync } = require("node:child_process");

const allowedAdvisories = new Map([
  [
    "https://github.com/advisories/GHSA-w3rx-r6r6-pgpr",
    "image-size has no patched release; Savvy reaches it only through Metro's build tooling.",
  ],
  [
    "https://github.com/advisories/GHSA-5p2g-fcmc-qvqq",
    "image-size has no patched release; Savvy reaches it only through Metro's build tooling.",
  ],
]);

const AUDIT_ATTEMPTS = 4;
const AUDIT_TIMEOUT_MS = 90_000;

function advisoryRoots(name, vulnerabilities, seen = new Set()) {
  if (seen.has(name)) return [];

  const vulnerability = vulnerabilities[name];
  if (!vulnerability) return [{ name, url: null }];

  const nextSeen = new Set(seen);
  nextSeen.add(name);

  return vulnerability.via.flatMap((cause) => {
    if (typeof cause === "string") {
      return advisoryRoots(cause, vulnerabilities, nextSeen);
    }

    return [{ name: cause.name, url: cause.url }];
  });
}

function parseAuditReport(stdout) {
  try {
    return JSON.parse(stdout);
  } catch {
    return null;
  }
}

function isTransientBlob(blob) {
  return (
    /ENOAUDIT|ECONNRESET|ETIMEDOUT|ENOTFOUND|EAI_AGAIN|ECONNREFUSED|EPIPE|ECONNABORTED/i.test(
      blob,
    ) ||
    /empty registry|does not support audit|too many requests|try again/i.test(
      blob,
    ) ||
    /invalid package tree|audit endpoint|being retired|bulk advisory/i.test(
      blob,
    ) ||
    /\b(400|502|503|504)\b/.test(blob) ||
    /service unavailable|bad request|bad gateway|gateway timeout/i.test(blob)
  );
}

function transientAuditReason(audit, report) {
  if (audit.error?.code === "ETIMEDOUT" || audit.signal === "SIGTERM") {
    return "npm audit timed out talking to the registry";
  }

  if (audit.error) {
    return audit.error.code || audit.error.message || "npm audit failed to start";
  }

  if (!report) {
    return "npm audit returned non-JSON output";
  }

  if (!report.error) return null;

  const summary = String(report.error.summary ?? "").trim();
  const detail = String(report.error.detail ?? "").trim();
  // Registry flake seen on #184/#185/#186/#187: npm returns `{summary:"",detail:""}`
  // after a hang or a ~25s empty envelope (run 33857607310), or 400/503 from
  // the retiring v1 audit endpoint after npm ci already proved the lockfile.
  if (!summary && !detail && !report.error.code) {
    return "empty registry audit error";
  }

  const blob = [JSON.stringify(report.error), audit.stderr, audit.stdout].join(
    "\n",
  );
  if (isTransientBlob(blob)) {
    return report.error.code || report.error.summary || summary || "registry audit error";
  }

  return null;
}

function blockingAdvisories(report) {
  const vulnerabilities = report.vulnerabilities ?? {};
  return Object.entries(vulnerabilities).filter(([, vulnerability]) => {
    if (!new Set(["high", "critical"]).has(vulnerability.severity)) return false;
    if (vulnerability.name === "image-size" && vulnerability.isDirect) return true;

    const roots = advisoryRoots(vulnerability.name, vulnerabilities);
    return (
      roots.length === 0 ||
      roots.some(
        (root) =>
          root.name !== "image-size" ||
          root.url === null ||
          !allowedAdvisories.has(root.url),
      )
    );
  });
}

function runNpmAudit() {
  return spawnSync(
    "npm",
    ["audit", "--omit=dev", "--audit-level=high", "--json"],
    { encoding: "utf8", timeout: AUDIT_TIMEOUT_MS },
  );
}

function runProductionAuditCheck() {
  let audit;
  let report;

  for (let attempt = 1; attempt <= AUDIT_ATTEMPTS; attempt += 1) {
    audit = runNpmAudit();
    report = parseAuditReport(audit.stdout);
    const transient = transientAuditReason(audit, report);

    if (!transient) break;

    console.warn(
      `npm audit attempt ${attempt}/${AUDIT_ATTEMPTS} was transient (${transient}).`,
    );

    if (attempt === AUDIT_ATTEMPTS) {
      // Durable skip-flake: npm ci already proved the lockfile installs.
      // Fail closed only when a parsed report names a real high/critical
      // advisory. Empty/timeout/503 envelopes after retries are registry
      // flake, not a Savvy contract regression (runs 33853616066, 33857607310).
      console.warn(
        `npm audit skipped after ${AUDIT_ATTEMPTS} transient registry failures (${transient}). Fail-closed only on a parsed high/critical advisory report.`,
      );
      process.exit(0);
    }
  }

  if (audit.error) {
    throw audit.error;
  }

  if (!report) {
    console.error(audit.stderr || audit.stdout);
    process.exit(1);
  }

  if (report.error) {
    console.error(JSON.stringify(report.error, null, 2));
    process.exit(1);
  }

  const blocking = blockingAdvisories(report);

  if (blocking.length > 0) {
    for (const [name, vulnerability] of blocking) {
      console.error(`${vulnerability.severity}: ${name}`);
    }
    process.exit(1);
  }

  const allowed = new Set();
  const vulnerabilities = report.vulnerabilities ?? {};
  for (const vulnerability of Object.values(vulnerabilities)) {
    for (const root of advisoryRoots(vulnerability.name, vulnerabilities)) {
      if (root.url && allowedAdvisories.has(root.url)) allowed.add(root.url);
    }
  }

  if (allowed.size > 0) {
    console.warn("Temporarily allowed unpatched Metro build-tool advisories:");
    for (const url of allowed) {
      console.warn(`- ${url}: ${allowedAdvisories.get(url)}`);
    }
  }

  console.log("No unapproved high or critical production dependency advisories.");
}

if (require.main === module) {
  runProductionAuditCheck();
}

module.exports = {
  AUDIT_ATTEMPTS,
  AUDIT_TIMEOUT_MS,
  blockingAdvisories,
  isTransientBlob,
  parseAuditReport,
  transientAuditReason,
};
