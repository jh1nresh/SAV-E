import { randomUUID } from "node:crypto";
import { mkdir, open, rename, unlink } from "node:fs/promises";
import { dirname, join } from "node:path";
import { publicDiscoveryMaxFileBytes } from "./publicDiscovery.js";

export type Job = {
  identity: string;
  pending: boolean;
  dueAt: number;
  catalogDueAt?: number;
};

export type QueueState = {
  version: 1;
  backoffUntil: number;
  catalogAfter?: number;
  jobs: Job[];
};

export const emptyPublicSourceQueue: QueueState = { version: 1, backoffUntil: 0, jobs: [] };

export function parsePublicSourceQueue(value: unknown, currentIdentities: ReadonlySet<string>): QueueState {
  const raw = value as Partial<QueueState> | null;
  const timestamp = (entry: unknown): entry is number =>
    Number.isSafeInteger(entry) && (entry as number) >= 0 && (entry as number) <= 8.64e15;
  if (!raw || raw.version !== 1 || !timestamp(raw.backoffUntil) || !Array.isArray(raw.jobs)
    || (raw.catalogAfter !== undefined && !timestamp(raw.catalogAfter))) {
    throw new Error("Invalid public source queue state");
  }
  const identities = new Set<string>();
  const jobs: Job[] = [];
  for (const entry of raw.jobs) {
    if (!entry || typeof entry.identity !== "string" || entry.identity.length > 450 || identities.has(entry.identity)
      || typeof entry.pending !== "boolean" || !timestamp(entry.dueAt)
      || (entry.catalogDueAt !== undefined && !timestamp(entry.catalogDueAt))) {
      throw new Error("Invalid public source queue job");
    }
    identities.add(entry.identity);
    if (currentIdentities.has(entry.identity)) {
      jobs.push({ identity: entry.identity, pending: entry.pending, dueAt: entry.dueAt,
        ...(entry.catalogDueAt === undefined ? {} : { catalogDueAt: entry.catalogDueAt }) });
    }
  }
  return { version: 1, backoffUntil: raw.backoffUntil, jobs,
    ...(raw.catalogAfter === undefined ? {} : { catalogAfter: raw.catalogAfter }) };
}

export async function writePublicSourceJSON(path: string, value: unknown, maxBytes = publicDiscoveryMaxFileBytes): Promise<void> {
  const data = JSON.stringify(value) + "\n";
  if (Buffer.byteLength(data) > maxBytes) throw new Error("Public source queue file is too large");
  const temporary = path + "." + randomUUID() + ".tmp";
  const handle = await open(temporary, "wx", 0o600);
  try {
    try {
      await handle.writeFile(data);
      await handle.sync();
    } finally {
      await handle.close();
    }
    await rename(temporary, path);
    const directory = await open(dirname(path), "r");
    try {
      await directory.sync();
    } finally {
      await directory.close();
    }
  } finally {
    await unlink(temporary).catch((error: NodeJS.ErrnoException) => {
      if (error.code !== "ENOENT") throw error;
    });
  }
}

export async function openPublicSourceQueue(root: string, load: (file: string) => Promise<unknown>) {
  const dir = join(root, "queue");
  await mkdir(dir, { recursive: true, mode: 0o700 });
  const path = join(dir, "state.json");
  const value = await load(path).catch((error: NodeJS.ErrnoException) => {
    if (error.code === "ENOENT") return emptyPublicSourceQueue;
    throw error;
  });
  return { value, save: (state: QueueState) => writePublicSourceJSON(path, state) };
}
