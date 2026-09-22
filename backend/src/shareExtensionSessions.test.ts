import assert from "node:assert/strict";
import test from "node:test";
import { randomUUID } from "node:crypto";
import { readFile } from "node:fs/promises";
import {
  normalizeShareAnalyzeInput,
  shareAnalysisInputHash,
  shareExtensionAnalysisResponse,
  shareExtensionSessionTTLMillis,
  shareTokenHash,
  ShareExtensionSessionError,
  ShareExtensionSessionStore,
} from "./shareExtensionSessions.js";
import { runSourceSearchRecovery } from "./sourceSearchWorker.js";

type Row = Record<string, any>;

class FakeSharePool {
  sessions: Row[] = [];
  analyses = new Map<string, Row>();
  private advisoryBusy = false;
  private advisoryWaiters: Array<() => void> = [];
  async connect() { return Object.assign(this, { release() {} }); }
  async query(sql: string, values: unknown[] = []): Promise<{ rows: Row[]; rowCount: number }> {
    if (/^begin$/i.test(sql.trim())) return { rows: [], rowCount: 0 };
    if (/^(commit|rollback)$/i.test(sql.trim())) {
      this.advisoryBusy = false;
      this.advisoryWaiters.shift()?.();
      return { rows: [], rowCount: 0 };
    }
    if (sql.includes("pg_advisory_xact_lock")) {
      if (this.advisoryBusy) await new Promise<void>(resolve => this.advisoryWaiters.push(resolve));
      this.advisoryBusy = true;
      return { rows: [], rowCount: 0 };
    }
    if (sql.includes("share-extension:issue-revoke")) {
      let count = 0;
      for (const row of this.sessions) if (row.owner_id === values[0] && row.installation_id === values[1] && row.revoked_at === null) {
        row.revoked_at = values[2]; count += 1;
      }
      return { rows: [], rowCount: count };
    }
    if (sql.includes("share-extension:issue-insert")) {
      if (this.sessions.some(row => row.owner_id === values[0] && row.installation_id === values[2] && row.revoked_at === null)) {
        throw new Error("active installation uniqueness violation");
      }
      const row = { id: randomUUID(), owner_id: values[0], owner_subject: values[1], installation_id: values[2],
        token_hash: values[3], expires_at: values[4], created_at: values[5], revoked_at: null };
      this.sessions.push(row); return { rows: [row], rowCount: 1 };
    }
    if (sql.includes("share-extension:authorize")) {
      const row = this.sessions.find(item => item.token_hash === values[0] && item.revoked_at === null
        && item.expires_at.getTime() > (values[1] as Date).getTime());
      return { rows: row ? [row] : [], rowCount: row ? 1 : 0 };
    }
    if (sql.includes("share-extension:revoke")) {
      const row = this.sessions.find(item => item.token_hash === values[0]);
      if (row && row.revoked_at === null) row.revoked_at = values[1];
      return { rows: [], rowCount: row ? 1 : 0 };
    }
    if (sql.includes("share-extension:analysis-claim")) {
      if (this.analyses.has(String(values[1]))) return { rows: [], rowCount: 0 };
      const row = { session_id: values[0], analysis_id: values[1], request_hash: values[2], status: "pending", response: null };
      this.analyses.set(String(values[1]), row); return { rows: [row], rowCount: 1 };
    }
    if (sql.includes("share-extension:analysis-existing")) {
      const row = this.analyses.get(String(values[0])); return { rows: row ? [row] : [], rowCount: row ? 1 : 0 };
    }
    if (sql.includes("share-extension:analysis-complete")) {
      const row = this.analyses.get(String(values[1]));
      if (!row || row.session_id !== values[0] || row.request_hash !== values[2] || row.status !== "pending") return { rows: [], rowCount: 0 };
      row.status = "completed"; row.response = JSON.parse(String(values[3])); return { rows: [], rowCount: 1 };
    }
    if (sql.includes("share-extension:analysis-fail")) {
      const row = this.analyses.get(String(values[1]));
      if (row && row.session_id === values[0] && row.request_hash === values[2] && row.status === "pending") row.status = "failed";
      return { rows: [], rowCount: row ? 1 : 0 };
    }
    throw new Error(`Unexpected SQL: ${sql}`);
  }
}

test("share session issue stores only a token hash, scopes ownership, expires, reissues, and revokes itself", async () => {
  const pool = new FakeSharePool();
  const store = new ShareExtensionSessionStore(pool as any);
  const now = new Date("2026-09-22T00:00:00Z");
  const installation = randomUUID();
  const issued = await store.issue("profile-a", "did:privy:a", installation, now);
  assert.equal(Buffer.from(issued.token, "base64url").byteLength, 32);
  assert.equal(issued.session.expiresAt.getTime() - now.getTime(), shareExtensionSessionTTLMillis);
  assert.equal(pool.sessions[0].token_hash, shareTokenHash(issued.token));
  assert.ok(!JSON.stringify(pool.sessions).includes(issued.token));
  assert.equal((await store.authorize(issued.token, now)).ownerSubject, "did:privy:a");

  const other = await store.issue("profile-b", "did:privy:b", installation, now);
  assert.equal((await store.authorize(other.token, now)).ownerId, "profile-b", "same installation id in another account is isolated");
  const replacement = await store.issue("profile-a", "did:privy:a", installation, now);
  await assert.rejects(store.authorize(issued.token, now), error => error instanceof ShareExtensionSessionError && error.status === 401);
  assert.equal((await store.authorize(replacement.token, now)).ownerId, "profile-a");
  await assert.rejects(store.authorize(replacement.token, new Date(now.getTime() + shareExtensionSessionTTLMillis + 1)),
    error => error instanceof ShareExtensionSessionError && error.status === 401);
  await store.revoke(replacement.token, now); await store.revoke(replacement.token, now);
  await store.revoke("unknown-token", now);
  await assert.rejects(store.authorize(replacement.token, now), error => error instanceof ShareExtensionSessionError && error.status === 401);
});

test("concurrent renewal leaves exactly one active token for an owner installation", async () => {
  const pool = new FakeSharePool();
  const store = new ShareExtensionSessionStore(pool as any);
  const installation = randomUUID();
  const [first, second] = await Promise.all([
    store.issue("profile-a", "did:privy:a", installation),
    store.issue("profile-a", "did:privy:a", installation),
  ]);
  assert.equal(pool.sessions.filter(row => row.owner_id === "profile-a" && row.installation_id === installation && row.revoked_at === null).length, 1);
  await assert.rejects(store.authorize(first.token), error => error instanceof ShareExtensionSessionError && error.status === 401);
  assert.equal((await store.authorize(second.token)).ownerSubject, "did:privy:a");
});

test("share analysis claims prevent concurrent billing, replay cached output, and reject id/input or owner substitution", async () => {
  const pool = new FakeSharePool();
  const store = new ShareExtensionSessionStore(pool as any);
  const id = randomUUID(), firstSession = randomUUID(), secondSession = randomUUID();
  const input = normalizeShareAnalyzeInput({ source_url: "https://www.instagram.com/reel/fixture/", caption: "Fixture", analysis_id: id });
  const hash = shareAnalysisInputHash(input);
  assert.deepEqual(await store.claimAnalysis(firstSession, id, hash), { kind: "new" });
  await assert.rejects(store.claimAnalysis(firstSession, id, hash), /already in progress/);
  await assert.rejects(store.claimAnalysis(firstSession, id, "0".repeat(64)), /different input/);
  await assert.rejects(store.claimAnalysis(secondSession, id, hash), /different input/);
  const response = { owner_subject: "did:privy:a", candidates: [], receipt: { output: "source_only_clue" } };
  await store.completeAnalysis(firstSession, id, hash, response);
  assert.deepEqual(await store.claimAnalysis(firstSession, id, hash), { kind: "replay", response });
});

test("inline share analysis accepts the provided smith&hsu caption and returns a map-verifiable review candidate", async () => {
  const caption = "smith&hsu 中山旗艦店 台北市中山區中山北路二段50巷31號";
  const input = normalizeShareAnalyzeInput({
    source_url: "https://www.instagram.com/reel/smith-hsu-fixture/",
    caption,
    analysis_id: randomUUID(),
  });
  let receivedCaption = "";
  const output = await runSourceSearchRecovery({ sourceUrl: input.sourceUrl, semanticSourceText: input.caption },
    async () => "", async () => [], {
      includeMediaEvidence: false,
      sourceDocumentResolver: async url => ({ html: "", resolution: {
        originalURL: url, resolvedURL: url, redirectChain: [url], status: "resolved",
      } }),
      semanticAnalyzer: async source => {
        receivedCaption = source.caption;
        return { status: "ready", venues: [{
          name: { value: "smith&hsu", quote: "smith&hsu", source: "caption" },
          branch: { value: "中山旗艦店", quote: "中山旗艦店", source: "caption" },
          address: { value: "台北市中山區中山北路二段50巷31號", quote: "台北市中山區中山北路二段50巷31號", source: "caption" },
          transport: null, mapStatus: "matched", matches: [{ id: "fixture-smith-hsu", name: "smith&hsu 中山旗艦店",
            address: "台北市中山區中山北路二段50巷31號", latitude: 25.055, longitude: 121.522 }],
        }] };
      },
    });
  assert.equal(receivedCaption, caption);
  assert.equal(output.semanticStatus, "ready");
  assert.equal(output.candidates[0]?.placeId, "fixture-smith-hsu");
  assert.equal(output.candidates[0]?.address, "台北市中山區中山北路二段50巷31號");
  assert.equal(shareExtensionAnalysisResponse("did:privy:a", output).owner_subject, "did:privy:a");
  assert.throws(() => shareExtensionAnalysisResponse("did:privy:a", {
    ...output,
    candidates: [],
    receipt: { ...output.receipt, failureReason: { kind: "provider_failure", stage: "source" } },
  }), error => error instanceof ShareExtensionSessionError && error.status === 502);
});

test("share input rejects unsupported URLs, captions, ids, and API fields", () => {
  const id = randomUUID();
  assert.equal(normalizeShareAnalyzeInput({ source_url: "https://vm.tiktok.com/fixture", analysis_id: id }).sourceUrl,
    "https://vm.tiktok.com/fixture");
  for (const body of [
    { source_url: "http://instagram.com/reel/a", analysis_id: id },
    { source_url: "https://127.0.0.1/a", analysis_id: id },
    { source_url: "https://example.com/a", analysis_id: id },
    { source_url: "https://instagram.com/a", caption: 42, analysis_id: id },
    { source_url: "https://instagram.com/a", analysis_id: "not-a-uuid" },
    { source_url: "https://instagram.com/a", analysis_id: id, unexpected: true },
  ]) assert.throws(() => normalizeShareAnalyzeInput(body), ShareExtensionSessionError);
});

test("server keeps the share token route-scoped and inline analysis has no unconfirmed place writes", async () => {
  const source = await readFile(new URL("../src/server.ts", import.meta.url), "utf8");
  const routeIndex = source.indexOf('resource === "share-extension"');
  const normalAuthIndex = source.indexOf("const userId = await resolveUserId(request)");
  assert.ok(routeIndex > 0 && routeIndex < normalAuthIndex);
  const resolver = source.slice(source.indexOf("async function resolveUserId"), source.indexOf("async function profileIdForPrivySubject"));
  assert.doesNotMatch(resolver, /x-save-share-token/);
  const handler = source.slice(source.indexOf("async function handleShareExtension"), source.indexOf("function requiredShareExtensionToken"));
  assert.doesNotMatch(handler, /insert into\s+(places|captures|place_candidates)/i);
  assert.match(handler, /shareExtensionAnalysisResponse/);
  assert.match(handler, /analysisUsageStore\.start\(session\.ownerId, input\.analysisId, false, true\)/);
});
