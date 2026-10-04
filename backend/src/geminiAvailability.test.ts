import assert from "node:assert/strict";
import test from "node:test";
import { GeminiAvailability } from "./geminiAvailability.js";

test("passive availability distinguishes billing, quotas, recovery and stale observations", async () => {
  let now = 1000; const notices: string[] = [];
  const monitor = new GeminiAvailability(() => now, state => notices.push(state));
  assert.equal(monitor.snapshot().state, "unknown");
  const body = new Response("private provider detail", {status:402});
  assert.equal(await monitor.observe("a", async () => body), body);
  assert.equal(body.bodyUsed, false);
  assert.equal(monitor.snapshot().state, "billing_blocked");
  await monitor.observe("a", async () => new Response("", {status:402}));
  assert.equal(notices.length,1);
  await monitor.observe("b", async () => new Response(""));
  assert.equal(monitor.snapshot().state,"billing_blocked", "another model must not hide a billing failure");
  await monitor.observe("a", async () => new Response(""));
  assert.equal(monitor.snapshot().state,"available");
  await monitor.observe("a", async () => new Response("", {status:429}));
  assert.equal(monitor.snapshot().state,"rate_limited");
  assert.equal(monitor.snapshot().credit_balance,null);
  assert.ok(!JSON.stringify(monitor.snapshot()).includes("private"));
  now += 600_000;
  assert.equal(monitor.snapshot().state,"unknown");
});

test("late responses cannot overwrite a newer observed request and transport errors stay unchanged", async () => {
  const monitor = new GeminiAvailability(Date.now, () => {});
  let release!: (response:Response) => void;
  const old = monitor.observe("a", () => new Promise<Response>(resolve => {release=resolve;}));
  await monitor.observe("a", async () => new Response("",{status:403}));
  release(new Response("")); await old;
  assert.equal(monitor.snapshot().state,"access_denied");
  const error = new Error("secret transport detail");
  await assert.rejects(monitor.observe("a", async () => {throw error;}), value => value === error);
  assert.equal(monitor.snapshot().state,"unavailable");
  await monitor.observe("a", async () => new Response("",{status:400}));
  assert.equal(monitor.snapshot().state,"unavailable");
});
