import { test } from "node:test";
import assert from "node:assert/strict";
import { createRemote, mergeCustom, mergeItems, mergeSettings, toISO } from "../src/lib/sync-core.ts";

const UID = "11111111-2222-3333-4444-555555555555";
const item = (id: number, at = 1000) => ({ key: `movie-${id}`, id, type: "movie" as const, title: `T${id}`, poster: null, backdrop: null, year: null, date: null, rating: null, overview: null, genres: [], addedAt: at });
const keys = (l: { key: string }[]) => l.map((i) => i.key).sort();

test("first sync is a pure union", () => {
  const m = mergeItems([item(1), item(2)], [item(2), item(3)], null);
  assert.deepEqual(keys(m.merged), ["movie-1", "movie-2", "movie-3"]);
  assert.deepEqual(keys(m.add), ["movie-1"]);
  assert.deepEqual(m.removeKeys, []);
  assert.equal(m.pulled, 1);
});

test("later syncs honour removals on either side", () => {
  const base = new Set(["movie-1", "movie-2", "movie-3"]);
  // 1 removed here, 3 removed on the account, 4 added here, 5 added there
  const m = mergeItems([item(2), item(3), item(4)], [item(1), item(2), item(5)], base);
  assert.deepEqual(keys(m.merged), ["movie-2", "movie-4", "movie-5"]);
  assert.deepEqual(m.removeKeys, ["movie-1"]);
  assert.deepEqual(keys(m.add), ["movie-4"]);
});

test("custom lists: union, rename wins when edited here, deletes only for lists synced before", () => {
  const L = (id: string, name: string, items = [item(1)]) => ({ id, name, items, createdAt: 1 });
  const R = (id: string, name: string, items = [item(1)]) => ({ id, name, items, createdAt: 1, maxSort: 4 });
  const base = { a: { name: "A", items: ["movie-1"] }, b: { name: "B", items: ["movie-1"] }, c: { name: "C", items: ["movie-1"] } };
  const m = mergeCustom([L("a", "A2"), L("b", "B"), L("new", "N")], [R("a", "A"), R("b", "B"), R("c", "C"), R("other", "O")], base);
  assert.deepEqual(m.renameLists, [{ id: "a", name: "A2" }]);
  assert.deepEqual(m.deleteLists, ["c"]); // removed here, synced before
  assert.deepEqual(m.createLists.map((l) => l.id), ["new"]);
  assert.deepEqual(m.merged.map((l) => l.id).sort(), ["a", "b", "new", "other"]);
});

test("settings: local edits win, otherwise the account, services union on first sync", () => {
  const local = { region: "GB", hideAdult: true, autoPlayTrailers: true, trailersMuted: true, showTrailersInDetails: true, services: [8] };
  const first = mergeSettings(local, { region: "US", services: [9] }, null);
  assert.equal(first.merged.region, "US");
  assert.deepEqual(first.merged.services.sort(), [8, 9]);
  const base = { ...local, region: "GB" };
  const later = mergeSettings({ ...local, region: "DE" }, { region: "FR", hideAdult: false }, base);
  assert.equal(later.merged.region, "DE");
  assert.equal(later.merged.hideAdult, false);
  assert.deepEqual(later.push, { region: "DE" });
});

test("dates are written without fractional seconds", () => {
  assert.equal(toISO(1700000000123), "2023-11-14T22:13:20Z");
});

function mockFetch(handler: (url: URL, init: RequestInit) => { status?: number; body?: unknown }) {
  const calls: { method: string; url: URL; body: unknown }[] = [];
  const fn = (async (input: string, init: RequestInit) => {
    const url = new URL(input);
    calls.push({ method: init.method ?? "GET", url, body: init.body ? JSON.parse(init.body as string) : undefined });
    const r = handler(url, init);
    const status = r.status ?? 200;
    return new Response(status === 204 ? null : JSON.stringify(r.body ?? []), { status });
  }) as unknown as typeof fetch;
  return { fn, calls };
}
const remoteWith = (fn: typeof fetch) => createRemote({ url: "https://x.test", anonKey: "anon", userId: UID, getToken: async () => "tok", fetchImpl: fn, now: () => 0 });

test("reads and writes are scoped to the signed-in user and use iOS column names", async () => {
  const { fn, calls } = mockFetch(() => ({ body: [] }));
  const r = remoteWith(fn);
  await r.fetchMedia();
  await r.addMedia("want", [item(7)]);
  await r.removeMedia("liked", ["tv-9"]);
  await r.deleteList("abc-1");
  await r.pushSettings({ hideAdult: false, services: [8] });
  assert.equal(calls[0].url.searchParams.get("device_id"), `eq.${UID}`);
  assert.equal(calls[1].method, "POST");
  assert.deepEqual(calls[1].body, [{ device_id: UID, list_type: "want_to_watch", media_id: 7, media_type: "movie", title: "T7", poster_path: null, backdrop_path: null, year: null, release_date: null, vote_average: null, overview: null, added_at: "1970-01-01T00:00:01Z" }]);
  const del = calls[2];
  assert.equal(del.method, "DELETE");
  assert.equal(del.url.searchParams.get("device_id"), `eq.${UID}`);
  assert.equal(del.url.searchParams.get("list_type"), "eq.liked");
  assert.equal(del.url.searchParams.get("media_id"), "eq.9");
  // every DELETE carries the user filter
  for (const c of calls.filter((c) => c.method === "DELETE")) assert.ok((c.url.searchParams.get("user_id") ?? c.url.searchParams.get("device_id")) === `eq.${UID}`);
  const settings = calls[calls.length - 1];
  assert.equal(settings.url.searchParams.get("on_conflict"), "user_id");
  assert.equal((settings.body as { include_adult: boolean }[])[0].include_adult, true);
});

test("a missing table or blocked write is reported, not retried", async () => {
  const missing = remoteWith(mockFetch(() => ({ status: 404, body: { code: "PGRST205" } })).fn);
  await assert.rejects(missing.fetchMedia(), (e: { kind: string }) => e.kind === "missing");
  const denied = remoteWith(mockFetch(() => ({ status: 403, body: { code: "42501" } })).fn);
  await assert.rejects(denied.addMedia("want", [item(1)]), (e: { kind: string }) => e.kind === "denied");
});

test("a duplicate row (409) is skipped one by one", async () => {
  let n = 0;
  const { fn, calls } = mockFetch(() => (n++ === 0 ? { status: 409, body: { code: "23505" } } : n === 2 ? { status: 409 } : { status: 201 }));
  await remoteWith(fn).addMedia("watched", [item(1), item(2)]);
  assert.equal(calls.length, 3);
});

test("refuses a malformed user id", () => {
  assert.throws(() => createRemote({ url: "https://x.test", anonKey: "a", userId: "x&or=(1=1)", getToken: async () => "t" }));
});
