// Durable per-number SLL-R buyer identity + recurring-run notification dedup.
//
// SLL-R binds a buyer's orders / receipts / saved card to a buyerId via a session
// token. Savvy must reuse the SAME token for a given phone across restarts, or
// recurring (which polls + confirms per buyer) loses the identity. This replaces
// the previous in-memory Map with Postgres, mirroring sendbluePlaceStore: an
// injected pg-pool-like `query` so tests can fake it and there's no circular
// import on server.ts.

import type { Queryable } from "./sendbluePlaceStore.js";
import type { SllrBuyer } from "./sllrCommerce.js";

export const sllrBuyerTableSql = `
create table if not exists sendblue_sllr_buyers (
  number text primary key,
  token text not null,
  buyer_id text not null,
  created_at timestamptz not null default now()
);
create table if not exists sendblue_sllr_notified_runs (
  run_id text primary key,
  notified_at timestamptz not null default now()
);
`;

export type NumberBuyer = { number: string; buyer: SllrBuyer };

export class SllrBuyerStore {
  constructor(private readonly db: Queryable) {}

  async get(number: string): Promise<SllrBuyer | null> {
    const { rows } = await this.db.query(
      `select token, buyer_id from sendblue_sllr_buyers where number = $1`,
      [number],
    );
    const r = rows[0];
    return r ? { token: String(r.token), buyerId: String(r.buyer_id) } : null;
  }

  async set(number: string, buyer: SllrBuyer): Promise<void> {
    await this.db.query(
      `insert into sendblue_sllr_buyers (number, token, buyer_id)
       values ($1, $2, $3)
       on conflict (number) do update set token = excluded.token, buyer_id = excluded.buyer_id`,
      [number, buyer.token, buyer.buyerId],
    );
  }

  // Every known buyer — the notifier polls each for pending recurring runs.
  async all(): Promise<NumberBuyer[]> {
    const { rows } = await this.db.query(`select number, token, buyer_id from sendblue_sllr_buyers`);
    return rows.map((r) => ({
      number: String(r.number),
      buyer: { token: String(r.token), buyerId: String(r.buyer_id) },
    }));
  }

  // Atomic dedup: returns true ONLY the first time a run id is seen, so a run is
  // notified exactly once even across overlapping notifier passes / instances.
  async markNotified(runId: string): Promise<boolean> {
    const { rows } = await this.db.query(
      `insert into sendblue_sllr_notified_runs (run_id) values ($1)
       on conflict do nothing returning run_id`,
      [runId],
    );
    return rows.length > 0;
  }
}
