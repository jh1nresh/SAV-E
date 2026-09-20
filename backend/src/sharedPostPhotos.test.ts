import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { sharedPostPhotos, sanitizedJPEG, sharedPostBodyMaxBytes } from "./sharedPostPhotos.js";
import { getSharedPostPhoto, putSharedPost } from "./sharedPosts.js";
import type { Pool } from "pg";

const jpeg = await readFile(new URL("../fixtures/shared-posts/photo.jpg", import.meta.url));
const encoded = jpeg.toString("base64");

test("photo attachments distinguish omitted, empty, and three images", () => {
  assert.equal(sharedPostPhotos(undefined), undefined);
  assert.deepEqual(sharedPostPhotos([]), []);
  const photos = sharedPostPhotos([encoded, encoded, encoded])!;
  assert.equal(photos.length, 3);
  assert.deepEqual(sanitizedJPEG(photos[0]), photos[0], "re-editing normalized images is lossless");
  assert.ok(Buffer.byteLength(JSON.stringify({ photos: Array(3).fill(Buffer.alloc(262144).toString("base64")), caption: "😀".repeat(500) })) < sharedPostBodyMaxBytes);
});

test("metadata is stripped; malformed, unbounded and non-JPEG media is rejected", () => {
  const metadata = Buffer.from("Exif GPS PRIVATE");
  const app = Buffer.alloc(metadata.length + 4);
  app.writeUInt16BE(0xffe1); app.writeUInt16BE(metadata.length + 2, 2); metadata.copy(app, 4);
  const clean = sanitizedJPEG(Buffer.concat([jpeg.subarray(0, 2), app, jpeg.subarray(2)]));
  assert.ok(!clean.includes(metadata));
  assert.deepEqual(clean, sanitizedJPEG(jpeg));
  for (const value of [null, {}, [encoded, encoded, encoded, encoded], [null], ["https://example.invalid/a.jpg"], ["abcd"], [encoded + "\n"], [Buffer.alloc(262145).toString("base64")]]) {
    assert.throws(() => sharedPostPhotos(value), { status: 400 });
  }
  for (const value of [jpeg.subarray(0, -2), Buffer.concat([jpeg, Buffer.from("trailing private data")]), jpeg.subarray(0, 20)]) {
    assert.throws(() => sanitizedJPEG(value), { status: 400 });
  }
  const large = Buffer.from(jpeg), frame = large.indexOf(Buffer.from([0xff, 0xc0]));
  assert.ok(frame > 0); large.writeUInt16BE(1601, frame + 7);
  assert.throws(() => sanitizedJPEG(large), { status: 400 });
});

test("bad media and indexes fail before acquiring a database connection", async () => {
  const pool = {} as Pool;
  const id = "a1111111-1111-4111-8111-111111111111";
  await assert.rejects(putSharedPost(pool, "owner", id, { status: "visited", stars: null, caption: "", photos: ["invalid"] }), { status: 400 });
  for (const index of ["-1", "3", "1.0", "00", "1 OR TRUE"])
    await assert.rejects(getSharedPostPhoto(pool, "viewer", id, index), { status: 404 });
});
