// Per-number verified-visit memory for the Sendblue iMessage bot.
//
// When a user forwards/texts a purchase receipt, we extract the merchant and
// store it keyed by their phone number as a VERIFIED VISIT — proof they were
// actually there. This is the receipt-gated-review primitive (the TruCritic
// thesis): a review only counts once a matching visit is on record.
//
// Backed by an injected pg-pool-like query function (NOT the pool directly) so
// server.ts wires in `pool.query` and tests inject a fake — same pattern as
// sendbluePlaceStore, no circular import on server.ts.
//
// Unlike saved places, visits are NOT de-duplicated: the same person can visit
// the same place many times, and each receipt is a distinct verified visit.

export type VerifiedVisit = {
  merchant: string;
  total?: string;
  visitDate?: string;
  raw?: string;
  createdAt?: Date;
};

/** Minimal pg-pool-like surface: only `query` is needed. */
export type Queryable = {
  query: (sql: string, values?: unknown[]) => Promise<{ rows: Record<string, unknown>[] }>;
};

export interface VerifiedVisitStore {
  /** Record a verified visit for a phone. Returns the phone's total visit count. */
  save(phone: string, visit: VerifiedVisit): Promise<number>;
  /** Most-recent verified visits for a phone (default limit 15). */
  list(phone: string, limit?: number): Promise<VerifiedVisit[]>;
}

export const verifiedVisitsTableSql = `
create table if not exists sendblue_verified_visits (
  id serial primary key,
  phone text not null,
  merchant text not null,
  total text,
  visit_date text,
  raw text,
  created_at timestamptz not null default now()
);
create index if not exists sendblue_verified_visits_phone_created_idx
  on sendblue_verified_visits (phone, created_at desc);
`;

export class PgVerifiedVisitStore implements VerifiedVisitStore {
  constructor(private readonly db: Queryable) {}

  async save(phone: string, visit: VerifiedVisit): Promise<number> {
    await this.db.query(
      `insert into sendblue_verified_visits (phone, merchant, total, visit_date, raw)
       values ($1, $2, $3, $4, $5)`,
      [
        phone,
        visit.merchant.trim(),
        visit.total?.trim() || null,
        visit.visitDate?.trim() || null,
        // Cap raw so an unexpectedly large forwarded message can't bloat the row.
        visit.raw?.slice(0, 2000) || null,
      ],
    );
    const counted = await this.db.query(
      `select count(*)::int as count from sendblue_verified_visits where phone = $1`,
      [phone],
    );
    const count = counted.rows[0]?.count;
    return typeof count === "number" ? count : Number(count ?? 0);
  }

  async list(phone: string, limit = 15): Promise<VerifiedVisit[]> {
    const { rows } = await this.db.query(
      `select merchant, total, visit_date, created_at
       from sendblue_verified_visits
       where phone = $1
       order by created_at desc
       limit $2`,
      [phone, limit],
    );
    return rows.map((row) => ({
      merchant: String(row.merchant ?? ""),
      total: row.total ? String(row.total) : undefined,
      visitDate: row.visit_date ? String(row.visit_date) : undefined,
      createdAt: row.created_at instanceof Date ? row.created_at : undefined,
    }));
  }
}
