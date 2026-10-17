"use client";

/**
 * Keeps the browser's lists, custom lists and StreamQ/settings in step with the signed-in account.
 * Signed out, none of this runs and the app stays purely local.
 *
 * One cycle (`reconcile`) is idempotent: read the account, three-way merge with this browser using
 * the keys both sides had at the last sync, apply the result locally, then push only the
 * difference. Because of that a failed push is simply retried as another cycle, which is the whole
 * offline queue. Backend calls are all in ./sync-core (createRemote).
 */

import { useSyncExternalStore } from "react";
import { AUTH_ENABLED, getAccessToken, getUser, onAuthChange } from "./auth";
import { applySynced, clearLocalData, getState, onLocalChange, onLocalReset, type CustomList, type ListId } from "./store";
import {
  customBase, createRemote, isUUID, LIST_IDS, mergeCustom, mergeItems, mergeKeys, mergeRatings, mergeSettings, pickSynced, SyncError,
  type CustomBase, type Remote, type SyncedSettings,
} from "./sync-core";

/**
 * Lists, ratings and episodes sync into per-user tables that must exist first (web/sync-tables.sql).
 * Until the owner has run it every request gets a "table missing" error, shown in the account card,
 * and nothing is written.
 */
const SYNC_LISTS = true;

const META_KEY = "watchguide.sync.v1";
const URL_BASE = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? "").replace(/\/+$/, "");
const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

type Phase = "off" | "syncing" | "synced" | "error";
export interface SyncStatus { phase: Phase; lastSyncAt: number | null; error: string | null; notice: string | null }

/** What was in sync last time, per area. An area missing here has never synced successfully. */
interface Meta {
  userId: string; // the account this browser's data belongs to; kept after sign-out so a different account clears it
  lists?: Record<ListId, string[]>;
  custom?: CustomBase;
  ratings?: Record<string, number>;
  episodes?: string[];
  settings?: SyncedSettings;
  lastSyncAt?: number;
  notice?: string | null;
}

let meta: Meta | null = null;
let status: SyncStatus = { phase: "off", lastSyncAt: null, error: null, notice: null };
const listeners = new Set<() => void>();
let started = false;
let timer: ReturnType<typeof setTimeout> | undefined;
let failures = 0;
let running = false;
let again = false;
let activeUser: string | null = null;

function readMeta(): Meta | null {
  try { return JSON.parse(window.localStorage.getItem(META_KEY) ?? "null") as Meta | null; } catch { return null; }
}
function writeMeta(m: Meta | null) {
  meta = m;
  try {
    if (m) window.localStorage.setItem(META_KEY, JSON.stringify(m));
    else window.localStorage.removeItem(META_KEY);
  } catch {}
}
function setStatus(patch: Partial<SyncStatus>) {
  status = { ...status, ...patch };
  listeners.forEach((l) => l());
}

export function dismissSyncNotice() {
  if (meta) writeMeta({ ...meta, notice: null });
  setStatus({ notice: null });
}

export function useSyncStatus(): SyncStatus {
  return useSyncExternalStore(
    (l) => { listeners.add(l); return () => listeners.delete(l); },
    () => status,
    () => status,
  );
}

/* ------------------------------------------------------------------ cycle */

const plural = (n: number, w: string) => `${n} ${w}${n === 1 ? "" : "s"}`;

async function reconcile(remote: Remote, userId: string): Promise<void> {
  const base = meta?.userId === userId ? meta : { userId };
  const next: Meta = { ...base, userId };
  const errors: string[] = [];
  let pulled = 0, pushed = 0;
  const firstTime = !base.lists && SYNC_LISTS;

  // The account can change while a request is in flight; never apply or push one account's data as another's.
  const still = () => { if (getUser()?.id !== userId) throw new SyncError("auth", "Account changed."); };
  const guard = async (area: string, fn: () => Promise<void>) => {
    try { await fn(); } catch (e) {
      if (e instanceof SyncError && e.kind === "auth") throw e;
      errors.push(e instanceof SyncError ? e.message : `${area} failed.`);
    }
  };

  if (SYNC_LISTS) await guard("Lists", async () => {
    const theirs = await remote.fetchMedia();
    still();
    const mine = getState().lists; // read straight after the await so nothing is lost between merge and apply
    const results = LIST_IDS.map((id) => ({ id, m: mergeItems(mine[id], theirs[id], base.lists ? new Set(base.lists[id]) : null) }));
    applySynced((s) => ({ ...s, lists: { ...s.lists, ...Object.fromEntries(results.map((r) => [r.id, r.m.merged])) } }));
    for (const { id, m } of results) {
      await remote.addMedia(id, m.add);
      await remote.removeMedia(id, m.removeKeys);
      pulled += m.pulled; pushed += m.pushed;
    }
    next.lists = Object.fromEntries(results.map((r) => [r.id, r.m.merged.map((i) => i.key)])) as Record<ListId, string[]>;
  });

  if (SYNC_LISTS) await guard("Custom lists", async () => {
    const theirs = await remote.fetchCustom();
    still();
    const mine = getState().custom;
    const m = mergeCustom(mine, theirs, base.custom ?? null);
    applySynced((s) => ({ ...s, custom: m.merged }));
    for (const l of m.createLists) await remote.createList(l);
    for (const r of m.renameLists) await remote.renameList(r.id, r.name);
    for (const id of m.deleteLists) await remote.deleteList(id);
    const sortOf = new Map(theirs.map((r) => [r.id.toLowerCase(), r.maxSort + 1]));
    const byList = new Map<string, typeof m.addItems>();
    m.addItems.forEach((a) => byList.set(a.listId, [...(byList.get(a.listId) ?? []), a]));
    for (const l of m.createLists) byList.set(l.id, l.items.map((item) => ({ listId: l.id, item })));
    for (const [listId, adds] of byList) await remote.addListItems(listId, adds.map((a) => a.item), sortOf.get(listId.toLowerCase()) ?? 0);
    const removals = new Map<string, string[]>();
    m.removeItems.forEach((r) => removals.set(r.listId, [...(removals.get(r.listId) ?? []), r.key]));
    for (const [listId, keys] of removals) await remote.removeListItems(listId, keys);
    pulled += m.pulled; pushed += m.pushed;
    next.custom = customBase(m.merged);
  });

  const episodeKeys = (eps: Record<string, string[]>) => Object.entries(eps).flatMap(([id, codes]) => codes.map((c) => `${id}:${c}`));
  await guard("Ratings", async () => {
    const theirs = await remote.fetchRatings();
    still();
    const m = mergeRatings(getState().ratings, theirs, base.ratings ?? null);
    applySynced((s) => ({ ...s, ratings: m.merged }));
    await remote.setRatings(m.set);
    await remote.clearRatings(m.clear);
    next.ratings = m.merged;
  });

  await guard("Episodes", async () => {
    const theirs = await remote.fetchEpisodes();
    still();
    const m = mergeKeys(episodeKeys(getState().episodes), theirs, base.episodes ? new Set(base.episodes) : null);
    const eps: Record<string, string[]> = {};
    for (const k of m.merged) { const [id, code] = k.split(":"); (eps[id] ??= []).push(code); }
    applySynced((s) => ({ ...s, episodes: eps }));
    await remote.addEpisodes(m.add);
    await remote.removeEpisodes(m.removeKeys);
    next.episodes = m.merged;
  });

  await guard("Settings", async () => {
    const theirs = await remote.fetchSettings();
    still();
    const m = mergeSettings(pickSynced(getState().settings), theirs, base.settings ?? null);
    applySynced((s) => ({ ...s, settings: { ...s.settings, ...m.merged } }));
    await remote.pushSettings(m.push);
    next.settings = m.merged;
  });

  next.lastSyncAt = Date.now();
  if (firstTime && next.lists && (pulled || pushed)) {
    next.notice = pulled
      ? `We found ${plural(pulled, "title")} on your account and combined them with what was on this browser${pushed ? `, and added ${plural(pushed, "title")} from here to your account` : ""}. Nothing was removed.`
      : `We added ${plural(pushed, "title")} from this browser to your account. Nothing was removed.`;
  } else next.notice = base.notice ?? null;
  writeMeta(next);
  setStatus({ lastSyncAt: next.lastSyncAt, notice: next.notice ?? null });
  if (errors.length) throw new SyncError("other", errors[0]);
}

async function run() {
  const user = getUser();
  if (!AUTH_ENABLED || !user) { setStatus({ phase: "off", error: null }); return; }
  if (running) { again = true; return; }
  running = true;
  setStatus({ phase: "syncing", error: null });
  try {
    const remote = createRemote({ url: URL_BASE, anonKey: ANON_KEY, userId: user.id, getToken: getAccessToken });
    // Two tabs must not reconcile at once, or both would push the same titles.
    const locks = typeof navigator !== "undefined" ? navigator.locks : undefined;
    if (locks) await locks.request("watchguide-sync", () => reconcile(remote, user.id));
    else await reconcile(remote, user.id);
    failures = 0;
    setStatus({ phase: "synced", error: null });
  } catch (e) {
    const err = e as SyncError;
    failures++;
    setStatus({ phase: "error", error: err.kind === "network" ? "Offline. Will retry." : err.message });
    if (err.kind !== "missing" && err.kind !== "denied" && err.kind !== "auth") schedule(Math.min(5000 * 2 ** (failures - 1), 300_000));
  } finally {
    running = false;
    if (again) { again = false; schedule(500); }
  }
}

function schedule(ms: number) {
  if (typeof window === "undefined") return;
  clearTimeout(timer);
  timer = setTimeout(run, ms);
}

/** Sync now (focus, reconnect, "Sync now"). */
export function syncNow() { schedule(0); }

/* ---------------------------------------------------------------- sessions */

function onAccountChange() {
  const user = getUser();
  if ((user?.id ?? null) === activeUser && started && meta) return; // token refresh, not a different account
  activeUser = user?.id ?? null;
  meta = readMeta();
  if (!user) {
    clearTimeout(timer);
    setStatus({ phase: "off", error: null, notice: null });
    return; // data stays on this browser; meta keeps the account id so another account can't inherit it
  }
  // Another account than the one this data belongs to: start clean, as the iOS app does in saveSession.
  if (meta && meta.userId !== user.id) {
    clearLocalData();
    writeMeta(null);
  }
  if (!meta) writeMeta({ userId: user.id });
  setStatus({ lastSyncAt: meta?.lastSyncAt ?? null, notice: meta?.notice ?? null });
  failures = 0;
  schedule(0);
}

/** Local custom lists made before the account existed used short ids; the account tables want UUIDs. */
function normalizeListIds() {
  const bad = getState().custom.some((l) => !isUUID(l.id));
  if (!bad) return;
  applySynced((s) => ({ ...s, custom: s.custom.map((l: CustomList) => (isUUID(l.id) ? l : { ...l, id: crypto.randomUUID() })) }));
}

/** Start once, from a client component mounted in the layout. Safe to call repeatedly. */
export function startSync() {
  if (started || typeof window === "undefined" || !AUTH_ENABLED) return;
  started = true;
  normalizeListIds();
  onAuthChange(onAccountChange);
  onLocalChange(() => { if (getUser()) schedule(2500); });
  onLocalReset(() => {
    // Reset wipes this browser only: forget what was synced so the account's data comes back.
    if (meta && getUser()) writeMeta({ userId: meta.userId });
    if (getUser()) schedule(0);
  });
  window.addEventListener("focus", () => { if (getUser()) schedule(300); });
  window.addEventListener("online", () => { if (getUser()) schedule(300); });
  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible" && getUser()) schedule(300); });
  onAccountChange();
}
