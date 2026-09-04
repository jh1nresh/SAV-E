const assert = require("node:assert/strict");
const { test } = require("node:test");
const {
  blockingAdvisories,
  transientAuditReason,
} = require("./check-production-audit.js");

test("empty registry envelope is transient", () => {
  const reason = transientAuditReason(
    { status: 1, stdout: "", stderr: "" },
    { error: { summary: "", detail: "" } },
  );
  assert.equal(reason, "empty registry audit error");
});

test("spawn timeout is transient", () => {
  const reason = transientAuditReason(
    { error: { code: "ETIMEDOUT" }, signal: "SIGTERM", status: null },
    null,
  );
  assert.equal(reason, "npm audit timed out talking to the registry");
});

test("503 and invalid package tree envelopes are transient", () => {
  assert.match(
    transientAuditReason(
      { status: 1, stdout: "", stderr: "npm error 503 Service Unavailable" },
      { error: { summary: "503 Service Unavailable", detail: "" } },
    ),
    /503|registry audit error|Service Unavailable/,
  );
  assert.match(
    transientAuditReason(
      { status: 1, stdout: "", stderr: "" },
      {
        error: {
          summary: "Invalid package tree",
          detail: "The npm audit endpoint is being retired",
        },
      },
    ),
    /Invalid package tree|registry audit error/,
  );
});

test("parsed advisory report is not transient", () => {
  const reason = transientAuditReason(
    { status: 1, stdout: "", stderr: "" },
    {
      vulnerabilities: {
        leftpad: { name: "leftpad", severity: "high", via: [], isDirect: true },
      },
    },
  );
  assert.equal(reason, null);
});

test("fails closed on an unapproved high advisory", () => {
  const blocking = blockingAdvisories({
    vulnerabilities: {
      leftpad: {
        name: "leftpad",
        severity: "high",
        isDirect: true,
        via: [{ name: "leftpad", url: "https://github.com/advisories/GHSA-fake" }],
      },
    },
  });
  assert.equal(blocking.length, 1);
  assert.equal(blocking[0][0], "leftpad");
});
