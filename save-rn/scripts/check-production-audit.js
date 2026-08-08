const { spawnSync } = require("node:child_process");

const allowedAdvisories = new Map([
  [
    "https://github.com/advisories/GHSA-w3rx-r6r6-pgpr",
    "image-size has no patched release; SAV-E reaches it only through Metro's build tooling.",
  ],
  [
    "https://github.com/advisories/GHSA-5p2g-fcmc-qvqq",
    "image-size has no patched release; SAV-E reaches it only through Metro's build tooling.",
  ],
]);

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

const audit = spawnSync(
  "npm",
  ["audit", "--omit=dev", "--audit-level=high", "--json"],
  { encoding: "utf8" },
);

if (audit.error) {
  throw audit.error;
}

let report;
try {
  report = JSON.parse(audit.stdout);
} catch {
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
