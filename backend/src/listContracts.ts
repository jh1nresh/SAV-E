import type { JsonObject } from "./socialContracts.js";

export const listTitleMaxLength = 120;
export const listNoteMaxLength = 500;
export const listItemPayloadMaxBytes = 8 * 1024;
export const listMaxItems = 200;
export const listBodyMaxBytes = 16 * 1024;
export const listShareCodePattern = /^[A-Za-z0-9_-]{6,32}$/;
export const listShareBaseURL = "https://sav-e-app.vercel.app/list";
export const referralShareBaseURL = "https://sav-e-app.vercel.app/r";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export interface ListCreate {
  id?: string;
  title: string;
  note: string | null;
}

export interface ListItemCreate {
  payload: JsonObject;
}

export interface ListJoin {
  code: string;
}

export interface ListShareCodeCreate {
  role: "editor" | "viewer";
}

interface ListQueryResult {
  rows: JsonObject[];
}

export type ListQuery = (sql: string, values: readonly unknown[]) => Promise<ListQueryResult>;

export function normalizeListCreate(body: JsonObject): ListCreate {
  const id = optionalTrimmedString(body.id, "id");
  if (id !== undefined && !uuidPattern.test(id)) throw new Error("id must be a UUID");

  const title = optionalTrimmedString(body.title, "title");
  if (!title) throw new Error("title is required");
  if ([...title].length > listTitleMaxLength) {
    throw new Error(`title must be ${listTitleMaxLength} characters or fewer`);
  }

  const note = optionalTrimmedString(body.note, "note");
  if (note !== undefined && [...note].length > listNoteMaxLength) {
    throw new Error(`note must be ${listNoteMaxLength} characters or fewer`);
  }

  return { id, title, note: note ?? null };
}

export function normalizeListItemCreate(body: JsonObject): ListItemCreate {
  const payload = body.payload;
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    throw new Error("payload is required");
  }
  if (Buffer.byteLength(JSON.stringify(payload), "utf8") > listItemPayloadMaxBytes) {
    throw new Error("payload is too large");
  }
  return { payload: payload as JsonObject };
}

export function normalizeListJoin(body: JsonObject): ListJoin {
  const code = optionalTrimmedString(body.code, "code");
  if (!code) throw new Error("code is required");
  if (!listShareCodePattern.test(code)) throw new Error("code is invalid");
  return { code };
}

export function normalizeShareCodeCreate(body: JsonObject): ListShareCodeCreate {
  const role = body.role;
  if (role !== "editor" && role !== "viewer") {
    throw new Error("role must be editor or viewer");
  }
  return { role };
}

const memberListSelect = `select
  l.id::text as id,
  l.owner_id,
  l.title,
  l.note,
  l.created_at,
  l.updated_at,
  m.role as viewer_role,
  coalesce(
    (
      select json_agg(json_build_object(
        'id', li.id,
        'payload', li.payload,
        'added_by', li.added_by,
        'created_at', li.created_at
      ) order by li.created_at, li.id)
      from list_items li
      where li.list_id = l.id
    ),
    '[]'::json
  ) as items
from lists l
join list_members m on m.list_id = l.id and m.user_id = $1`;

export async function listsForMember(userId: string, query: ListQuery): Promise<JsonObject[]> {
  if (!userId.trim()) throw new Error("Authenticated user id is required");
  const { rows } = await query(
    `${memberListSelect}
order by l.created_at desc`,
    [userId],
  );
  return rows;
}

export async function listForMember(
  listId: string,
  userId: string,
  query: ListQuery,
): Promise<JsonObject | null> {
  if (!userId.trim()) throw new Error("Authenticated user id is required");
  if (!uuidPattern.test(listId)) return null;
  const { rows } = await query(
    `${memberListSelect}
where l.id = $2
limit 1`,
    [userId, listId],
  );
  return rows[0] ?? null;
}

export async function memberRole(
  listId: string,
  userId: string,
  query: ListQuery,
): Promise<string | null> {
  if (!userId.trim()) throw new Error("Authenticated user id is required");
  if (!uuidPattern.test(listId)) return null;
  const { rows } = await query(
    `select role
from list_members
where list_id = $1 and user_id = $2
limit 1`,
    [listId, userId],
  );
  const role = rows[0]?.role;
  return typeof role === "string" && role ? role : null;
}

export function formatListRow(row: JsonObject): JsonObject {
  return {
    id: stringOrNull(row.id),
    title: stringOrNull(row.title),
    note: stringOrNull(row.note),
    owner_id: stringOrNull(row.owner_id),
    viewer_role: stringOrNull(row.viewer_role),
    items: (Array.isArray(row.items) ? row.items : [])
      .filter((item): item is JsonObject => Boolean(item) && typeof item === "object" && !Array.isArray(item))
      .map((item) => formatListItemRow(item)),
    created_at: isoTimestamp(row.created_at),
    updated_at: isoTimestamp(row.updated_at),
  };
}

export function formatListItemRow(row: JsonObject): JsonObject {
  return {
    id: stringOrNull(row.id),
    payload: row.payload ?? null,
    added_by: stringOrNull(row.added_by),
    created_at: isoTimestamp(row.created_at),
  };
}

export function listShareURL(code: string, shareBaseURL = listShareBaseURL): string {
  return `${shareBaseURL.replace(/\/+$/, "")}?c=${code}`;
}

export function referralShareURL(code: string, shareBaseURL = referralShareBaseURL): string {
  return `${shareBaseURL.replace(/\/+$/, "")}/${code}`;
}

function optionalTrimmedString(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null) return undefined;
  if (typeof value !== "string") throw new Error(`${field} must be a string`);
  const trimmed = value.trim();
  return trimmed ? trimmed : undefined;
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" && value ? value : null;
}

function isoTimestamp(value: unknown): string | null {
  const date = value instanceof Date ? value : typeof value === "string" ? new Date(value) : null;
  if (!date || Number.isNaN(date.getTime())) return null;
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}
