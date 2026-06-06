import assert from "node:assert/strict";
import test from "node:test";
import { buildClearingBlockDraft, merkleRootForHashes } from "./clearingBlocks.js";

test("clearing block draft chains receipt hashes into deterministic block hash", () => {
  const block = buildClearingBlockDraft({
    chainNamespace: "save_place_recovery_v0",
    blockNumber: 7,
    previousBlockHash: "prev_hash",
    receipts: [
      { id: "receipt_1", receiptHash: "hash_a" },
      { id: "receipt_2", receiptHash: "hash_b" },
      { id: "receipt_3", receiptHash: "hash_c" },
    ],
  });
  const repeated = buildClearingBlockDraft({
    chainNamespace: "save_place_recovery_v0",
    blockNumber: 7,
    previousBlockHash: "prev_hash",
    receipts: [
      { id: "receipt_1", receiptHash: "hash_a" },
      { id: "receipt_2", receiptHash: "hash_b" },
      { id: "receipt_3", receiptHash: "hash_c" },
    ],
  });

  assert.equal(block.receiptCount, 3);
  assert.equal(block.merkleRoot, merkleRootForHashes(["hash_a", "hash_b", "hash_c"]));
  assert.equal(block.blockHash, repeated.blockHash);
});

test("clearing block hash changes when previous block changes", () => {
  const receipts = [{ id: "receipt_1", receiptHash: "hash_a" }];
  const first = buildClearingBlockDraft({
    chainNamespace: "save_place_recovery_v0",
    blockNumber: 2,
    previousBlockHash: "prev_a",
    receipts,
  });
  const second = buildClearingBlockDraft({
    chainNamespace: "save_place_recovery_v0",
    blockNumber: 2,
    previousBlockHash: "prev_b",
    receipts,
  });

  assert.notEqual(first.blockHash, second.blockHash);
});

test("clearing block hash commits to receipt order", () => {
  const first = buildClearingBlockDraft({
    chainNamespace: "save_place_recovery_v0",
    blockNumber: 1,
    receipts: [
      { id: "receipt_1", receiptHash: "hash_a" },
      { id: "receipt_2", receiptHash: "hash_b" },
    ],
  });
  const second = buildClearingBlockDraft({
    chainNamespace: "save_place_recovery_v0",
    blockNumber: 1,
    receipts: [
      { id: "receipt_2", receiptHash: "hash_b" },
      { id: "receipt_1", receiptHash: "hash_a" },
    ],
  });

  assert.notEqual(first.blockHash, second.blockHash);
});

test("clearing block requires at least one receipt", () => {
  assert.throws(() => buildClearingBlockDraft({
    chainNamespace: "save_place_recovery_v0",
    blockNumber: 1,
    receipts: [],
  }));
});
