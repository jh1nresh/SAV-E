export type StoredRelatedPlaceSourcePack = {
  pack: Record<string, unknown>;
  fetchedAt: string;
  requestedPlatforms: string[];
  maxResultsPerPlatform: number;
  querySet: string[];
};

type QueryResult = { rows: Array<Record<string, unknown>> };
type Query = (sql: string, values: readonly unknown[]) => Promise<QueryResult>;

export class PgRelatedPlaceSourcesStore {
  constructor(private readonly query: Query) {}

  async load(placeId: string, userId: string): Promise<StoredRelatedPlaceSourcePack | undefined> {
    const { rows } = await this.query(
      `select pack, fetched_at, requested_platforms, max_results_per_platform, query_set
       from related_place_source_packs
       where place_id = $1 and user_id = $2
       limit 1`,
      [placeId, userId],
    );
    const row = rows[0];
    if (!row) return undefined;

    return {
      pack: objectValue(row.pack, "pack"),
      fetchedAt: dateString(row.fetched_at, "fetched_at"),
      requestedPlatforms: stringArray(row.requested_platforms, "requested_platforms"),
      maxResultsPerPlatform: integerValue(row.max_results_per_platform, "max_results_per_platform"),
      querySet: stringArray(row.query_set, "query_set"),
    };
  }

  async save(
    placeId: string,
    userId: string,
    stored: StoredRelatedPlaceSourcePack,
  ): Promise<void> {
    await this.query(
      `insert into related_place_source_packs (
         place_id,
         user_id,
         pack,
         fetched_at,
         requested_platforms,
         max_results_per_platform,
         query_set
       ) values ($1, $2, $3::jsonb, $4, $5, $6, $7)
       on conflict (place_id) do update set
         user_id = excluded.user_id,
         pack = excluded.pack,
         fetched_at = excluded.fetched_at,
         requested_platforms = excluded.requested_platforms,
         max_results_per_platform = excluded.max_results_per_platform,
         query_set = excluded.query_set,
         updated_at = now()`,
      [
        placeId,
        userId,
        JSON.stringify(stored.pack),
        stored.fetchedAt,
        stored.requestedPlatforms,
        stored.maxResultsPerPlatform,
        stored.querySet,
      ],
    );
  }
}

function objectValue(value: unknown, field: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`Stored related-source ${field} is invalid`);
  }
  return value as Record<string, unknown>;
}

function dateString(value: unknown, field: string): string {
  const date = value instanceof Date ? value : new Date(String(value));
  if (Number.isNaN(date.getTime())) {
    throw new Error(`Stored related-source ${field} is invalid`);
  }
  return date.toISOString();
}

function stringArray(value: unknown, field: string): string[] {
  if (!Array.isArray(value) || value.some((entry) => typeof entry !== "string")) {
    throw new Error(`Stored related-source ${field} is invalid`);
  }
  return value;
}

function integerValue(value: unknown, field: string): number {
  if (!Number.isInteger(value)) {
    throw new Error(`Stored related-source ${field} is invalid`);
  }
  return Number(value);
}
