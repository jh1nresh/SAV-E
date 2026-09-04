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

const AUDIT_ATTEMPTS = 3;
const AUDIT_TIMEOUT_MS = 180_000;

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

  const blob = JSON.stringify(report.error);
  if (
    /ENOAUDIT|ECONNRESET|ETIMEDOUT|ENOTFOUND|EAI_AGAIN|ECONNREFUSED|EPIPE|ECONNABORTED/i.test(
      blob,
    ) ||
    /empty registry|does not support audit|too many requests|try again/i.test(blob)
  ) {
    return report.error.code || report.error.summary || "registry audit error";
  }

  return null;
}

function runNpmAudit() {
  return spawnSync(
    "npm",
    ["audit", "--omit=dev", "--audit-level=high", "--json"],
    { encoding: "utf8", timeout: AUDIT_TIMEOUT_MS },
  );
}

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
    if (report?.error) {
      console.error(JSON.stringify(report.error, null, 2));
    } else {
      console.error(audit.stderr || audit.stdout || transient);
    }
    process.exit(1);
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

const vulnerabilities = report.vulnerabilities ?? {};
const blocking = Object.entries(vulnerabilities).filter(([, vulnerability]) => {
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

if (blocking.length > 0) {
  for (const [name, vulnerability] of blocking) {
    console.error(`${vulnerability.severity}: ${name}`);
  }
  process.exit(1);
}

const allowed = new Set();
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
