// Per-number place memory for the Sendblue iMessage bot.
//
// Each place a user texts the bot is saved keyed by their phone number, so the
// bot becomes a personal place graph you text ("my places") rather than a
// stateless link analyzer.
//
// The store is backed by an injected pg-pool-like query function (NOT the pool
// directly) so server.ts wires in `pool.query` and tests inject a fake — this
// keeps the module free of a circular import on server.ts.

import type { ExtractedVenue } from "./sendblueBot.js";

export type SavedPlace = {
  name: string;
  area?: string;
  category?: string;
  sourceUrl?: string;
  createdAt?: Date;
};

/** A phone's last-known location (per-request location, remembered as a default). */
export type StoredLocation = { label: string; lat: number; lng: number };

/** Minimal pg-pool-like surface: only `query` is needed. */
export type Queryable = {
  query: (sql: string, values?: unknown[]) => Promise<{ rows: Record<string, unknown>[] }>;
};

/** Options for {@link SendbluePlaceStore.list}. Backward-compatible: a bare
 * number is still accepted as the limit. */
export type ListOpts = { limit?: number; area?: string };

export interface SendbluePlaceStore {
  /** Save (or refresh) a place for a phone. Returns the phone's total distinct place count. */
  save(phone: string, venue: ExtractedVenue, sourceUrl?: string): Promise<number>;
  /**
   * Most-recent saved places for a phone (default limit 15).
   * Accepts either a bare `limit` number (legacy) or an options object with an
   * optional `area` filter (case-insensitive partial match on the stored area).
   */
  list(phone: string, opts?: number | ListOpts): Promise<SavedPlace[]>;
  /** The distinct, non-empty `area` values this phone has saved (for area detection). */
  distinctAreas(phone: string): Promise<string[]>;
  /** The phone's last-known location (set when they tell the bot an area). null = unknown. */
  getLocation(phone: string): Promise<StoredLocation | null>;
  setLocation(phone: string, location: StoredLocation): Promise<void>;
}

/** Normalize the legacy `number` arg or the new options object into a shape. */
function normalizeListOpts(opts?: number | ListOpts): { limit: number; area?: string } {
  if (typeof opts === "number") return { limit: opts };
  return { limit: opts?.limit ?? 15, area: opts?.area };
}

export const sendblueSavedPlacesTableSql = `
create table if not exists sendblue_saved_places (
  id serial primary key,
  phone text not null,
  name text not null,
  area text,
  category text,
  source_url text,
  created_at timestamptz not null default now()
);
create index if not exists sendblue_saved_places_phone_created_idx
  on sendblue_saved_places (phone, created_at desc);

create table if not exists sendblue_user_locations (
  phone text primary key,
  label text not null default '',
  lat double precision not null,
  lng double precision not null,
  updated_at timestamptz not null default now()
);
`;

/**
 * Postgres-backed place memory. De-dups by (phone, lower(name)): re-sending the
 * same place refreshes created_at instead of inserting a duplicate row.
 */
export class PgSendbluePlaceStore implements SendbluePlaceStore {
  constructor(private readonly db: Queryable) {}

  async save(phone: string, venue: ExtractedVenue, sourceUrl?: string): Promise<number> {
    const name = venue.name.trim();
    const area = venue.area?.trim() || null;
    const category = venue.category?.trim() || null;
    const source = sourceUrl?.trim() || null;

    // De-dup: refresh an existing row for the same phone + case-insensitive name.
    const updated = await this.db.query(
      `update sendblue_saved_places
       set created_at = now(),
           area = coalesce($3, area),
           category = coalesce($4, category),
           source_url = coalesce($5, source_url)
       where phone = $1 and lower(name) = lower($2)
       returning id`,
      [phone, name, area, category, source],
    );

    if (updated.rows.length === 0) {
      await this.db.query(
        `insert into sendblue_saved_places (phone, name, area, category, source_url)
         values ($1, $2, $3, $4, $5)`,
        [phone, name, area, category, source],
      );
    }

    const counted = await this.db.query(
      `select count(distinct lower(name))::int as count
       from sendblue_saved_places
       where phone = $1`,
      [phone],
    );
    const count = counted.rows[0]?.count;
    return typeof count === "number" ? count : Number(count ?? 0);
  }

  async list(phone: string, opts?: number | ListOpts): Promise<SavedPlace[]> {
    const { limit, area } = normalizeListOpts(opts);
    // NOTE: `area` is a text filter on the user's stored area string — there is
    // no GPS/coordinates and therefore no true distance ranking. We honestly
    // approximate "near me" with a case-insensitive partial match (ILIKE) on the
    // area the user typed when they saved the place, most-recent first.
    const { rows } = area
      ? await this.db.query(
          `select name, area, category, source_url, created_at
           from sendblue_saved_places
           where phone = $1 and area ilike '%' || $2 || '%'
           order by created_at desc
           limit $3`,
          [phone, area, limit],
        )
      : await this.db.query(
          `select name, area, category, source_url, created_at
           from sendblue_saved_places
           where phone = $1
           order by created_at desc
           limit $2`,
          [phone, limit],
        );
    return rows.map((row) => ({
      name: String(row.name ?? ""),
      area: row.area ? String(row.area) : undefined,
      category: row.category ? String(row.category) : undefined,
      sourceUrl: row.source_url ? String(row.source_url) : undefined,
      createdAt: row.created_at instanceof Date ? row.created_at : undefined,
    }));
  }

  async distinctAreas(phone: string): Promise<string[]> {
    const { rows } = await this.db.query(
      `select distinct area
       from sendblue_saved_places
       where phone = $1 and area is not null and area <> ''`,
      [phone],
    );
    return rows
      .map((row) => (row.area ? String(row.area) : ""))
      .filter((area) => area.length > 0);
  }

  async getLocation(phone: string): Promise<StoredLocation | null> {
    const { rows } = await this.db.query(
      `select label, lat, lng from sendblue_user_locations where phone = $1`,
      [phone],
    );
    const row = rows[0];
    if (!row) return null;
    return { label: String(row.label ?? ""), lat: Number(row.lat), lng: Number(row.lng) };
  }

  async setLocation(phone: string, location: StoredLocation): Promise<void> {
    await this.db.query(
      `insert into sendblue_user_locations (phone, label, lat, lng, updated_at)
       values ($1, $2, $3, $4, now())
       on conflict (phone) do update set label = excluded.label, lat = excluded.lat, lng = excluded.lng, updated_at = now()`,
      [phone, location.label, location.lat, location.lng],
    );
  }
}
