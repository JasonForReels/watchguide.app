/**
 * Account sync, the backend-facing half. No React, no browser globals, no "@/" imports, so it runs
 * under `node --test` with a mocked fetch.
 *
 * Wire format = the iOS app's (SupabaseService.swift), so web and iPhone see the same rows:
 *   media_items        device_id(=user id) list_type(want_to_watch|watched|liked) media_id media_type
 *                      title poster_path backdrop_path year release_date vote_average overview added_at
 *   custom_lists       user_id list_id name description icon_name display_style created_at updated_at
 *   custom_list_items  user_id list_id media_id media_type title poster_path backdrop_path year
 *                      release_date vote_average overview sort_order added_at
 *   user_settings      user_id (on_conflict) region include_adult auto_play_trailers
 *                      auto_play_trailers_muted show_trailers_in_media_detail streamq_service_ids updated_at
 *
 * Unlike iOS (delete everything, re-insert), this only inserts what is missing and deletes a row
 * only when the person removed that exact title here. Every request is scoped to the signed-in
 * user's id. To move off Supabase, replace createRemote and keep the merge functions.
 */

import type { CustomList, ListId, Settings } from "./store";
import type { MediaType, SavedItem } from "./types";

/* ------------------------------------------------------------------ errors */

export type SyncErrorKind = "auth" | "missing" | "denied" | "network" | "other";

export class SyncError extends Error {
  kind: SyncErrorKind;
  status: number;
  constructor(kind: SyncErrorKind, message: string, status = 0) {
    super(message);
    this.kind = kind;
    this.status = status;
  }
}

/* ------------------------------------------------------------------- rows */

export const LIST_TYPE: Record<ListId, string> = { want: "want_to_watch", watched: "watched", liked: "liked" };
const LIST_BY_TYPE: Record<string, ListId> = { want_to_watch: "want", watched: "watched", liked: "liked" };
export const LIST_IDS: ListId[] = ["want", "watched", "liked"];

interface MediaFields {
  media_id: number;
  media_type: string;
  title: string;
  poster_path: string | null;
  backdrop_path: string | null;
  year: string | null;
  release_date: string | null;
  vote_average: number | null;
  overview: string | null;
  added_at: string | null;
}
export interface MediaRow extends MediaFields { device_id: string; list_type: string }
export interface ListRow { user_id: string; list_id: string; name: string; description?: string | null; icon_name?: string | null; display_style?: string | null; created_at: string | null; updated_at: string | null }
export interface ListItemRow extends MediaFields { user_id: string; list_id: string; sort_order: number }
export interface SettingsRow {
  user_id: string;
  region?: string | null;
  include_adult?: boolean | null;
  auto_play_trailers?: boolean | null;
  auto_play_trailers_muted?: boolean | null;
  show_trailers_in_media_detail?: boolean | null;
  streamq_service_ids?: number[] | null;
}

/** iOS decodes dates with .iso8601, which rejects fractional seconds, so write whole seconds. */
export const toISO = (ms: number) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, "Z");

function fromISO(s: string | null | undefined, fallback: number): number {
  const t = s ? Date.parse(s) : NaN;
  return Number.isFinite(t) ? t : fallback;
}

const isMedia = (t: string): t is MediaType => t === "movie" || t === "tv";

function toFields(i: SavedItem): MediaFields {
  return {
    media_id: i.id, media_type: i.type, title: i.title, poster_path: i.poster, backdrop_path: i.backdrop,
    year: i.year, release_date: i.date, vote_average: i.rating, overview: i.overview, added_at: toISO(i.addedAt),
  };
}

function fromFields(r: MediaFields, now: number): SavedItem | null {
  if (!isMedia(r.media_type) || !Number.isInteger(r.media_id)) return null;
  return {
    key: `${r.media_type}-${r.media_id}`, id: r.media_id, type: r.media_type, title: r.title ?? "",
    poster: r.poster_path ?? null, backdrop: r.backdrop_path ?? null, year: r.year ?? null, date: r.release_date ?? null,
    rating: r.vote_average ?? null, overview: r.overview ?? null, genres: [], addedAt: fromISO(r.added_at, now),
  };
}

/* --------------------------------------------------------------- settings */

export type SyncedSettings = Pick<Settings, "region" | "hideAdult" | "autoPlayTrailers" | "trailersMuted" | "showTrailersInDetails" | "services">;
const SETTING_KEYS: (keyof SyncedSettings)[] = ["region", "hideAdult", "autoPlayTrailers", "trailersMuted", "showTrailersInDetails", "services"];

export const pickSynced = (s: Settings): SyncedSettings => ({
  region: s.region, hideAdult: s.hideAdult, autoPlayTrailers: s.autoPlayTrailers,
  trailersMuted: s.trailersMuted, showTrailersInDetails: s.showTrailersInDetails, services: s.services,
});

/** Only the fields iOS also has; null/absent columns stay undefined so they never overwrite. */
export function settingsFromRow(r: SettingsRow | null): Partial<SyncedSettings> {
  if (!r) return {};
  const out: Partial<SyncedSettings> = {};
  if (typeof r.region === "string" && r.region) out.region = r.region;
  if (typeof r.include_adult === "boolean") out.hideAdult = !r.include_adult;
  if (typeof r.auto_play_trailers === "boolean") out.autoPlayTrailers = r.auto_play_trailers;
  if (typeof r.auto_play_trailers_muted === "boolean") out.trailersMuted = r.auto_play_trailers_muted;
  if (typeof r.show_trailers_in_media_detail === "boolean") out.showTrailersInDetails = r.show_trailers_in_media_detail;
  if (Array.isArray(r.streamq_service_ids)) out.services = r.streamq_service_ids.filter((n) => Number.isInteger(n));
  return out;
}

function settingsToRow(userId: string, p: Partial<SyncedSettings>, now: number): SettingsRow & { updated_at: string } {
  const row: SettingsRow & { updated_at: string } = { user_id: userId, updated_at: toISO(now) };
  if (p.region !== undefined) row.region = p.region;
  if (p.hideAdult !== undefined) row.include_adult = !p.hideAdult;
  if (p.autoPlayTrailers !== undefined) row.auto_play_trailers = p.autoPlayTrailers;
  if (p.trailersMuted !== undefined) row.auto_play_trailers_muted = p.trailersMuted;
  if (p.showTrailersInDetails !== undefined) row.show_trailers_in_media_detail = p.showTrailersInDetails;
  if (p.services !== undefined) row.streamq_service_ids = p.services;
  return row;
}

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

export interface SettingsMerge { merged: SyncedSettings; push: Partial<SyncedSettings> }

/**
 * Per field: changed here since the last sync -> here wins; otherwise the account's value wins.
 * With no baseline (first sync) the account wins where it has a value, and StreamQ services are unioned.
 */
export function mergeSettings(local: SyncedSettings, remote: Partial<SyncedSettings>, base: SyncedSettings | null): SettingsMerge {
  const merged = { ...local } as Record<string, unknown>;
  const push: Record<string, unknown> = {};
  for (const k of SETTING_KEYS) {
    const l = local[k], r = remote[k], b = base?.[k];
    let v: unknown = l;
    if (r === undefined) v = l;
    else if (!base) v = k === "services" ? [...new Set([...(r as number[]), ...(l as number[])])] : r;
    else v = same(l, b) ? r : l;
    merged[k] = v;
    // A column the account has no value for is only filled once this side has actually changed it.
    if (!same(v, r) && (r !== undefined ? true : !!base && !same(l, b))) push[k] = v;
  }
  return { merged: merged as unknown as SyncedSettings, push: push as Partial<SyncedSettings> };
}

/* ------------------------------------------------------------------ items */

export interface ItemsMerge { merged: SavedItem[]; add: SavedItem[]; removeKeys: string[]; pulled: number; pushed: number }

/**
 * Three-way union of one list. `base` is the set of keys both sides had at the last sync (null on
 * the first sync, which makes it a pure union: nothing is dropped from either side).
 */
export function mergeItems(local: SavedItem[], remote: SavedItem[], base: Set<string> | null): ItemsMerge {
  const L = new Map(local.map((i) => [i.key, i]));
  const R = new Map(remote.map((i) => [i.key, i]));
  const merged: SavedItem[] = [];
  const add: SavedItem[] = [];
  const removeKeys: string[] = [];
  let pulled = 0;
  for (const [k, l] of L) {
    const r = R.get(k);
    if (r) merged.push({ ...r, ...l, genres: l.genres.length ? l.genres : r.genres, poster: l.poster ?? r.poster, backdrop: l.backdrop ?? r.backdrop });
    else if (base?.has(k)) continue; // removed on the account since the last sync
    else { merged.push(l); add.push(l); }
  }
  for (const [k, r] of R) {
    if (L.has(k)) continue;
    if (base?.has(k)) removeKeys.push(k); // removed here since the last sync
    else { merged.push(r); pulled++; }
  }
  merged.sort((a, b) => b.addedAt - a.addedAt);
  return { merged, add, removeKeys, pulled, pushed: add.length };
}

/* ------------------------------------------------------------ custom lists */

export interface RemoteList { id: string; name: string; createdAt: number; items: SavedItem[]; maxSort: number }
export interface ListBase { name: string; items: string[] }
export type CustomBase = Record<string, ListBase>;

export interface CustomMerge {
  merged: CustomList[];
  createLists: CustomList[];
  renameLists: { id: string; name: string }[];
  deleteLists: string[];
  addItems: { listId: string; item: SavedItem }[];
  removeItems: { listId: string; key: string }[];
  pulled: number;
  pushed: number;
}

export function mergeCustom(local: CustomList[], remote: RemoteList[], base: CustomBase | null): CustomMerge {
  const out: CustomMerge = { merged: [], createLists: [], renameLists: [], deleteLists: [], addItems: [], removeItems: [], pulled: 0, pushed: 0 };
  const R = new Map(remote.map((r) => [r.id.toLowerCase(), r]));
  const seen = new Set<string>();
  for (const l of local) {
    const id = l.id.toLowerCase();
    seen.add(id);
    const r = R.get(id);
    const b = base?.[id];
    if (!r) {
      if (b) continue; // deleted on the account
      out.merged.push(l);
      out.createLists.push(l);
      out.pushed += l.items.length;
      continue;
    }
    let name = r.name;
    if (b && l.name !== b.name) { name = l.name; out.renameLists.push({ id: r.id, name }); }
    const m = mergeItems(l.items, r.items, b ? new Set(b.items) : null);
    m.add.forEach((item) => out.addItems.push({ listId: r.id, item }));
    m.removeKeys.forEach((key) => out.removeItems.push({ listId: r.id, key }));
    out.pulled += m.pulled;
    out.pushed += m.pushed;
    out.merged.push({ ...l, id: r.id, name, items: m.merged, createdAt: l.createdAt || r.createdAt });
  }
  for (const r of remote) {
    const id = r.id.toLowerCase();
    if (seen.has(id)) continue;
    if (base?.[id]) { out.deleteLists.push(r.id); continue; } // deleted here
    out.merged.push({ id: r.id, name: r.name, items: r.items, createdAt: r.createdAt });
    out.pulled += r.items.length;
  }
  return out;
}

export const customBase = (lists: CustomList[]): CustomBase =>
  Object.fromEntries(lists.map((l) => [l.id.toLowerCase(), { name: l.name, items: l.items.map((i) => i.key) }]));

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export const isUUID = (s: string) => UUID.test(s);

/* ----------------------------------------------------------------- remote */

export interface RemoteConfig {
  url: string;
  anonKey: string;
  userId: string;
  getToken: () => Promise<string | null>;
  fetchImpl?: typeof fetch;
  now?: () => number;
}

const PAGE = 1000;

export interface Remote {
  fetchMedia(): Promise<Record<ListId, SavedItem[]>>;
  addMedia(list: ListId, items: SavedItem[]): Promise<void>;
  removeMedia(list: ListId, keys: string[]): Promise<void>;
  fetchCustom(): Promise<RemoteList[]>;
  createList(l: CustomList): Promise<void>;
  renameList(id: string, name: string): Promise<void>;
  deleteList(id: string): Promise<void>;
  addListItems(listId: string, items: SavedItem[], firstSort: number): Promise<void>;
  removeListItems(listId: string, keys: string[]): Promise<void>;
  fetchSettings(): Promise<Partial<SyncedSettings>>;
  pushSettings(p: Partial<SyncedSettings>): Promise<void>;
}

export function createRemote(cfg: RemoteConfig): Remote {
  const { userId } = cfg;
  if (!isUUID(userId)) throw new SyncError("auth", "Unexpected account id.");
  const base = cfg.url.replace(/\/+$/, "");
  const doFetch = cfg.fetchImpl ?? ((...a: Parameters<typeof fetch>) => fetch(...a));
  const now = cfg.now ?? Date.now;

  async function http(method: string, table: string, query: Record<string, string>, body?: unknown, prefer?: string): Promise<unknown> {
    const token = await cfg.getToken();
    if (!token) throw new SyncError("auth", "Signed out.", 401);
    const qs = new URLSearchParams(query).toString();
    let res: Response;
    try {
      res = await doFetch(`${base}/rest/v1/${table}${qs ? `?${qs}` : ""}`, {
        method,
        headers: {
          "Content-Type": "application/json", apikey: cfg.anonKey, Authorization: `Bearer ${token}`,
          ...(prefer ? { Prefer: prefer } : {}),
        },
        body: body === undefined ? undefined : JSON.stringify(body),
      });
    } catch {
      throw new SyncError("network", "Couldn't reach the server.");
    }
    if (res.ok) return res.status === 204 ? null : await res.json().catch(() => null);
    const text = await res.text().catch(() => "");
    let code = "";
    try { code = (JSON.parse(text) as { code?: string }).code ?? ""; } catch {}
    if (res.status === 401) throw new SyncError("auth", "Your session expired. Sign in again.", 401);
    if (res.status === 404 || code === "PGRST205" || code === "42P01") throw new SyncError("missing", `Table ${table} doesn't exist on the account server.`, res.status);
    if (res.status === 403 || code === "42501") throw new SyncError("denied", `The account server blocked access to ${table}.`, res.status);
    throw new SyncError("other", `${table}: ${res.status} ${text.slice(0, 160)}`, res.status);
  }

  async function all<T>(table: string, filter: Record<string, string>, order: string): Promise<T[]> {
    const out: T[] = [];
    for (let offset = 0; ; offset += PAGE) {
      const rows = (await http("GET", table, { ...filter, order, limit: String(PAGE), offset: String(offset) })) as T[] | null;
      if (!rows?.length) break;
      out.push(...rows);
      if (rows.length < PAGE) break;
    }
    return out;
  }

  /** A batch insert; if a row collides (409) retry one by one and skip the duplicates. */
  async function insert(table: string, rows: object[]) {
    if (!rows.length) return;
    try {
      await http("POST", table, {}, rows);
    } catch (e) {
      if (!(e instanceof SyncError) || e.status !== 409) throw e;
      for (const row of rows) {
        try { await http("POST", table, {}, [row]); } catch (e2) { if (!(e2 instanceof SyncError) || e2.status !== 409) throw e2; }
      }
    }
  }

  const mine = (col: string) => ({ [col]: `eq.${userId}` });
  const parts = (key: string) => {
    const i = key.lastIndexOf("-");
    const type = key.slice(0, i), id = Number(key.slice(i + 1));
    if (!isMedia(type) || !Number.isInteger(id)) throw new SyncError("other", `Bad title key ${key}`);
    return { type, id };
  };
  const listFilter = (id: string) => {
    if (!/^[\w-]{1,64}$/.test(id)) throw new SyncError("other", "Bad list id.");
    return { list_id: `eq.${id}` };
  };

  return {
    async fetchMedia() {
      const rows = await all<MediaRow>("media_items", mine("device_id"), "list_type.asc,media_type.asc,media_id.asc");
      const out: Record<ListId, SavedItem[]> = { want: [], watched: [], liked: [] };
      for (const r of rows) {
        const list = LIST_BY_TYPE[r.list_type];
        const item = list && fromFields(r, now());
        if (item) out[list].push(item);
      }
      return out;
    },
    async addMedia(list, items) {
      await insert("media_items", items.map((i) => ({ device_id: userId, list_type: LIST_TYPE[list], ...toFields(i) })));
    },
    async removeMedia(list, keys) {
      for (const k of keys) {
        const { type, id } = parts(k);
        await http("DELETE", "media_items", { ...mine("device_id"), list_type: `eq.${LIST_TYPE[list]}`, media_type: `eq.${type}`, media_id: `eq.${id}` });
      }
    },
    async fetchCustom() {
      const lists = await all<ListRow>("custom_lists", mine("user_id"), "created_at.asc,list_id.asc");
      if (!lists.length) return [];
      const items = await all<ListItemRow>("custom_list_items", mine("user_id"), "list_id.asc,media_type.asc,media_id.asc");
      const by = new Map<string, ListItemRow[]>();
      items.forEach((i) => by.set(i.list_id, [...(by.get(i.list_id) ?? []), i]));
      return lists.map((l) => {
        const rows = by.get(l.list_id) ?? [];
        return {
          id: l.list_id, name: l.name, createdAt: fromISO(l.created_at, now()),
          items: rows.map((r) => fromFields(r, now())).filter((i): i is SavedItem => !!i).sort((a, b) => b.addedAt - a.addedAt),
          maxSort: rows.reduce((m, r) => Math.max(m, r.sort_order ?? 0), -1),
        };
      });
    },
    async createList(l) {
      await insert("custom_lists", [{
        user_id: userId, list_id: l.id, name: l.name, description: null, icon_name: "folder.fill",
        display_style: "row", created_at: toISO(l.createdAt), updated_at: toISO(now()),
      }]);
    },
    async renameList(id, name) {
      // Only name and updated_at: icon, description and style set on the iPhone stay as they are.
      await http("PATCH", "custom_lists", { ...mine("user_id"), ...listFilter(id) }, { name, updated_at: toISO(now()) });
    },
    async deleteList(id) {
      await http("DELETE", "custom_list_items", { ...mine("user_id"), ...listFilter(id) });
      await http("DELETE", "custom_lists", { ...mine("user_id"), ...listFilter(id) });
    },
    async addListItems(listId, items, firstSort) {
      listFilter(listId);
      await insert("custom_list_items", items.map((i, n) => ({ user_id: userId, list_id: listId, ...toFields(i), sort_order: firstSort + n })));
    },
    async removeListItems(listId, keys) {
      for (const k of keys) {
        const { type, id } = parts(k);
        await http("DELETE", "custom_list_items", { ...mine("user_id"), ...listFilter(listId), media_type: `eq.${type}`, media_id: `eq.${id}` });
      }
    },
    async fetchSettings() {
      const rows = (await http("GET", "user_settings", { ...mine("user_id"), limit: "1" })) as SettingsRow[] | null;
      return settingsFromRow(rows?.[0] ?? null);
    },
    async pushSettings(p) {
      if (!Object.keys(p).length) return;
      await http("POST", "user_settings", { on_conflict: "user_id" }, [settingsToRow(userId, p, now())], "resolution=merge-duplicates");
    },
  };
}
