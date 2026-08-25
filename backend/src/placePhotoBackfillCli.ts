import pg from "pg";
import { runPlacePhotoBackfill, type BackfillQuery } from "./placePhotoBackfill.js";

const { Pool } = pg;

async function main(): Promise<void> {
  const args = parseArgs(process.argv.slice(2));
  const databaseURL = requiredEnvironmentValue("DATABASE_URL");
  const apiKey = requiredEnvironmentValue("GOOGLE_PLACES_API_KEY");
  const pool = new Pool({
    connectionString: databaseURL,
    ssl: databaseSSLConfig(databaseURL),
  });
  const query: BackfillQuery = async (sql, values) => {
    const result = await pool.query(sql, [...values]);
    return { rows: result.rows as Record<string, unknown>[] };
  };

  try {
    const receipt = await runPlacePhotoBackfill({
      userId: args.userId,
      limit: args.limit,
      apply: args.apply,
      apiKey,
      query,
    });
    process.stdout.write(`${JSON.stringify(receipt)}\n`);
    if (receipt.failed > 0) process.exitCode = 1;
  } finally {
    await pool.end();
  }
}

function parseArgs(args: string[]): { userId: string; limit: number; apply: boolean } {
  const userIndex = args.indexOf("--user-id");
  const limitIndex = args.indexOf("--limit");
  const userId = userIndex >= 0 ? args[userIndex + 1]?.trim() : undefined;
  if (!userId) throw new Error("Usage: --user-id <owner-id> [--limit 1-100] [--apply]");

  const limitValue = limitIndex >= 0 ? args[limitIndex + 1] : "100";
  const limit = Number(limitValue);
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) {
    throw new Error("--limit must be an integer from 1 through 100");
  }

  const recognized = new Set(["--user-id", userId, "--limit", limitValue, "--apply"]);
  const unknown = args.filter((value) => !recognized.has(value));
  if (unknown.length > 0) throw new Error(`Unknown argument: ${unknown[0]}`);
  return { userId, limit, apply: args.includes("--apply") };
}

function requiredEnvironmentValue(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

function databaseSSLConfig(url: string): undefined | { rejectUnauthorized: boolean; ca?: string } {
  const sslMode = process.env.PGSSLMODE?.trim().toLowerCase();
  if (sslMode === "disable") return undefined;
  let hostname = "";
  try {
    hostname = new URL(url).hostname.toLowerCase();
  } catch {
    hostname = "";
  }
  if (hostname === "localhost" || hostname === "127.0.0.1" || hostname.endsWith(".railway.internal")) {
    return undefined;
  }
  if (sslMode === "no-verify") return { rejectUnauthorized: false };
  const ca = process.env.DATABASE_CA_CERT?.replace(/\\n/g, "\n");
  return ca ? { rejectUnauthorized: true, ca } : { rejectUnauthorized: true };
}

void main().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : "Photo backfill failed";
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
});
