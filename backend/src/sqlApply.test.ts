import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import test from "node:test";
import { fileURLToPath } from "node:url";

const friendRatingsURL = new URL("../sql/friend-ratings.sql", import.meta.url);
const applyScript = fileURLToPath(new URL("../scripts/apply-sql.sh", import.meta.url));

function statementOrder(sql: string): string[] {
  return sql
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => /^(create|alter|drop|insert|update|delete|do)\b/i.test(line));
}

test("friend-ratings.sql creates idx_places_id_user_id before the composite FK", async () => {
  const sql = await readFile(friendRatingsURL, "utf8");
  const indexAt = sql.search(/create unique index if not exists idx_places_id_user_id/i);
  const fkAt = sql.search(/references places\(id, user_id\)/i);
  assert.ok(indexAt >= 0, "idx_places_id_user_id IF NOT EXISTS is required");
  assert.ok(fkAt >= 0, "composite places(id, user_id) FK is required");
  assert.ok(indexAt < fkAt, "index must precede the composite FK");
  assert.match(sql, /create table if not exists friend_restaurant_ratings/i);
  assert.match(sql, /create table if not exists friend_rating_saves/i);
  assert.doesNotMatch(sql, /^\s*drop\b/im);
  assert.match(sql, /Never run on boot/i);
  const order = statementOrder(sql);
  assert.equal(order[0], "create unique index if not exists idx_places_id_user_id on places(id, user_id);");
  assert.match(order[1], /create table if not exists friend_restaurant_ratings/);
});

function runApply(args: string[], env: NodeJS.ProcessEnv = {}): Promise<{ code: number; out: string }> {
  return new Promise((resolve, reject) => {
    const child = spawn("bash", [applyScript, ...args], {
      env: { PATH: process.env.PATH, HOME: process.env.HOME, ...env },
      stdio: ["ignore", "pipe", "pipe"],
    });
    let out = "";
    child.stdout.on("data", (chunk) => {
      out += chunk;
    });
    child.stderr.on("data", (chunk) => {
      out += chunk;
    });
    child.on("error", reject);
    child.on("close", (code) => resolve({ code: code ?? 1, out }));
  });
}

test("apply-sql.sh dry-reads friend-ratings.sql without secrets or writes", async () => {
  const { code, out } = await runApply(["friend-ratings.sql"], {
    DATABASE_URL: "postgresql://secret-user:secret-pass@db.example.invalid:5432/save?sslmode=no-verify",
    PGSSLMODE: "no-verify",
  });
  assert.equal(code, 0, out);
  assert.match(out, /idx_places_id_user_id/);
  assert.match(out, /before composite FK/);
  assert.match(out, /dry-read only/);
  assert.match(out, /overriding legacy PGSSLMODE=no-verify/);
  assert.match(out, /PGSSLMODE=require psql/);
  assert.match(out, /-f sql\/friend-ratings\.sql/);
  assert.doesNotMatch(out, /-f backend\/sql\//);
  assert.doesNotMatch(out, /secret-user|secret-pass|example\.invalid/);
});

test("apply-sql.sh drops only sslmode and keeps other libpq query params", async () => {
  const { code, out } = await runApply(["--self-test"]);
  assert.equal(code, 0, out);
  assert.match(out, /apply-sql self-test passed/);
});

test("apply-sql.sh refuses a path outside backend/sql", async () => {
  const { code, out } = await runApply(["../package.json"]);
  assert.equal(code, 2, out);
  assert.match(out, /refusing path outside backend\/sql/);
});

test("apply-sql.sh --apply without DATABASE_URL fails closed", async () => {
  const { code, out } = await runApply(["friend-ratings.sql", "--apply"]);
  assert.equal(code, 2, out);
  assert.match(out, /DATABASE_URL is required/);
  assert.doesNotMatch(out, /applying/);
});
