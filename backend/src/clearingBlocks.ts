import { createHash } from "node:crypto";

export interface ClearingReceiptInput {
  id: string;
  receiptHash: string;
}

export interface ClearingBlockDraft {
  chainNamespace: string;
  blockNumber: number;
  previousBlockHash?: string;
  merkleRoot: string;
  receiptCount: number;
  blockHash: string;
  receiptHashes: string[];
}

export function buildClearingBlockDraft(input: {
  chainNamespace: string;
  blockNumber: number;
  previousBlockHash?: string;
  receipts: ClearingReceiptInput[];
}): ClearingBlockDraft {
  if (!input.receipts.length) throw new Error("Clearing block requires at least one receipt");
  const receiptHashes = input.receipts.map((receipt) => receipt.receiptHash);
  const merkleRoot = merkleRootForHashes(receiptHashes);
  const header = {
    chain_namespace: input.chainNamespace,
    block_number: input.blockNumber,
    previous_block_hash: input.previousBlockHash ?? null,
    merkle_root: merkleRoot,
    receipt_count: input.receipts.length,
    receipt_hashes: receiptHashes,
  };

  return {
    chainNamespace: input.chainNamespace,
    blockNumber: input.blockNumber,
    previousBlockHash: input.previousBlockHash,
    merkleRoot,
    receiptCount: input.receipts.length,
    blockHash: sha256Hex(stableStringify(header)),
    receiptHashes,
  };
}

export function merkleRootForHashes(hashes: string[]): string {
  if (!hashes.length) return sha256Hex("");
  let level = hashes.map((hash) => sha256Hex(hash));
  while (level.length > 1) {
    const next: string[] = [];
    for (let index = 0; index < level.length; index += 2) {
      const left = level[index];
      const right = level[index + 1] ?? left;
      next.push(sha256Hex(`${left}${right}`));
    }
    level = next;
  }
  return level[0];
}

function sha256Hex(value: string): string {
  return createHash("sha256").update(value).digest("hex");
}

function stableStringify(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value);
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  const object = value as Record<string, unknown>;
  return `{${Object.keys(object).sort().map((key) => `${JSON.stringify(key)}:${stableStringify(object[key])}`).join(",")}}`;
}
