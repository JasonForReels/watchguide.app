"use client";

import { useRef, useSyncExternalStore } from "react";
import type { MediaType, SavedItem } from "./types";

/**
 * Everything the web app remembers lives here, in localStorage. It mirrors
 * the iOS `StorageService`: three built-in lists, custom lists, episode
 * progress, ratings and settings.
 */
export type ListId = "want" | "watched" | "liked";

export const LIST_META: Record<ListId, { name: string }> = {
  want: { name: "Want to Watch" },
  watched: { name: "Watched" },
  liked: { name: "Liked" },
};

export interface CustomList {
  id: string;
  name: string;
  items: SavedItem[];
  createdAt: number;
}

export interface Settings {
  theme: string;
  scheme: "system" | "dark" | "light";
  region: string;
  services: number[];
  hideAdult: boolean;
  /** Browse hero plays each title's trailer (iOS: Auto-play Trailers). */
  autoPlayTrailers: boolean;
  /** Shared mute choice for every autoplaying trailer (iOS: Mute Trailers on Autoplay). */
  trailersMuted: boolean;
  /** Title page header plays the trailer (iOS: Show Trailers in Media Details). */
  showTrailersInDetails: boolean;
}

export interface WatchEvent {
  key: string;
  at: number;
  minutes: number;
}

export interface State {
  version: 1;
  lists: Record<ListId, SavedItem[]>;
  custom: CustomList[];
  /** showId -> ["1x3", ...] */
  episodes: Record<string, string[]>;
  /** "movie-1" -> 1..5 */
  ratings: Record<string, number>;
  /** Tonight deck: keys swiped away so they don't come back. */
  skipped: string[];
  /** Watch log used by Stats and the activity heatmap. */
  log: WatchEvent[];
  searches: string[];
  settings: Settings;
}

const KEY = "watchguide.v1";

const initial: State = {
  version: 1,
  lists: { want: [], watched: [], liked: [] },
  custom: [],
  episodes: {},
  ratings: {},
  skipped: [],
  log: [],
  searches: [],
  settings: { theme: "marquee", scheme: "system", region: "US", services: [], hideAdult: true, autoPlayTrailers: true, trailersMuted: true, showTrailersInDetails: true },
};

let state: State = initial;
let loaded = false;
const listeners = new Set<() => void>();

function load() {
  if (loaded || typeof window === "undefined") return;
  loaded = true;
  try {
    const raw = window.localStorage.getItem(KEY);
    if (raw) {
      const parsed = JSON.parse(raw) as Partial<State>;
      state = {
        ...initial,
        ...parsed,
        lists: { ...initial.lists, ...parsed.lists },
        settings: { ...initial.settings, ...parsed.settings },
      };
    }
  } catch {
    // Private mode or corrupt data: start fresh rather than crash.
  }
  window.addEventListener("storage", (e) => {
    if (e.key !== KEY || !e.newValue) return;
    try {
      state = JSON.parse(e.newValue);
      listeners.forEach((l) => l());
    } catch {}
  });
}

function set(next: State | ((s: State) => State)) {
  load();
  state = typeof next === "function" ? next(state) : next;
  try {
    window.localStorage.setItem(KEY, JSON.stringify(state));
  } catch {}
  listeners.forEach((l) => l());
}

function subscribe(l: () => void) {
  load();
  listeners.add(l);
  return () => listeners.delete(l);
}

export function getState(): State {
  load();
  return state;
}

/**
 * Subscribe to a slice. Returns the initial state during SSR so markup stays
 * stable. The result is memoised per state object, so selectors may derive
 * new arrays without triggering render loops.
 */
export function useStore<T>(selector: (s: State) => T): T {
  const memo = useRef<{ s: State; v: T } | null>(null);
  const select = (s: State) => {
    if (memo.current?.s !== s) memo.current = { s, v: selector(s) };
    return memo.current.v;
  };
  return useSyncExternalStore(
    subscribe,
    () => select(getState()),
    () => select(initial),
  );
}

/** True once the browser store has been read, for hiding empty states during hydration. */
export function useHydrated(): boolean {
  return useSyncExternalStore(subscribe, () => true, () => false);
}

const without = (items: SavedItem[], key: string) => items.filter((i) => i.key !== key);

function runtimeGuess(item: SavedItem): number {
  return item.type === "movie" ? 110 : 45;
}

export const actions = {
  toggle(list: ListId, item: SavedItem) {
    set((s) => {
      const has = s.lists[list].some((i) => i.key === item.key);
      const lists = { ...s.lists, [list]: has ? without(s.lists[list], item.key) : [{ ...item, addedAt: Date.now() }, ...s.lists[list]] };
      // Watching something takes it off the watchlist, like on iOS.
      if (!has && list === "watched") lists.want = without(lists.want, item.key);
      const log = !has && list === "watched" && item.type === "movie"
        ? [...s.log, { key: item.key, at: Date.now(), minutes: runtimeGuess(item) }]
        : s.log;
      return { ...s, lists, log };
    });
  },
  add(list: ListId, item: SavedItem) {
    if (!getState().lists[list].some((i) => i.key === item.key)) actions.toggle(list, item);
  },
  remove(list: ListId, key: string) {
    set((s) => ({ ...s, lists: { ...s.lists, [list]: without(s.lists[list], key) } }));
  },
  rate(key: string, stars: number) {
    set((s) => {
      const ratings = { ...s.ratings };
      if (stars <= 0 || ratings[key] === stars) delete ratings[key];
      else ratings[key] = stars;
      return { ...s, ratings };
    });
  },
  createList(name: string): string {
    const id = Math.random().toString(36).slice(2, 10);
    set((s) => ({ ...s, custom: [...s.custom, { id, name: name.trim() || "Untitled list", items: [], createdAt: Date.now() }] }));
    return id;
  },
  renameList(id: string, name: string) {
    set((s) => ({ ...s, custom: s.custom.map((l) => (l.id === id ? { ...l, name } : l)) }));
  },
  deleteList(id: string) {
    set((s) => ({ ...s, custom: s.custom.filter((l) => l.id !== id) }));
  },
  toggleInCustom(id: string, item: SavedItem) {
    set((s) => ({
      ...s,
      custom: s.custom.map((l) => {
        if (l.id !== id) return l;
        const has = l.items.some((i) => i.key === item.key);
        return { ...l, items: has ? without(l.items, item.key) : [{ ...item, addedAt: Date.now() }, ...l.items] };
      }),
    }));
  },
  toggleEpisode(show: SavedItem, season: number, episode: number, runtime?: number | null) {
    set((s) => {
      const id = String(show.id);
      const code = `${season}x${episode}`;
      const current = s.episodes[id] ?? [];
      const has = current.includes(code);
      const episodes = { ...s.episodes, [id]: has ? current.filter((c) => c !== code) : [...current, code] };
      const log = has ? s.log : [...s.log, { key: show.key, at: Date.now(), minutes: runtime || 45 }];
      // Starting a show puts it in Watching (want list) so Up Next can find it.
      const lists = !has && !s.lists.want.some((i) => i.key === show.key) && !s.lists.watched.some((i) => i.key === show.key)
        ? { ...s.lists, want: [{ ...show, addedAt: Date.now() }, ...s.lists.want] }
        : s.lists;
      return { ...s, episodes, log, lists };
    });
  },
  markSeason(show: SavedItem, season: number, episodes: number[], watched: boolean) {
    set((s) => {
      const id = String(show.id);
      const codes = episodes.map((e) => `${season}x${e}`);
      const current = new Set(s.episodes[id] ?? []);
      const added = codes.filter((c) => !current.has(c)).length;
      codes.forEach((c) => (watched ? current.add(c) : current.delete(c)));
      const log = watched && added ? [...s.log, { key: show.key, at: Date.now(), minutes: added * 45 }] : s.log;
      return { ...s, episodes: { ...s.episodes, [id]: [...current] }, log };
    });
  },
  skip(key: string) {
    set((s) => ({ ...s, skipped: [...s.skipped.filter((k) => k !== key), key].slice(-500) }));
  },
  unskip(key: string) {
    set((s) => ({ ...s, skipped: s.skipped.filter((k) => k !== key) }));
  },
  resetSkipped() {
    set((s) => ({ ...s, skipped: [] }));
  },
  rememberSearch(q: string) {
    const query = q.trim();
    if (!query) return;
    set((s) => ({ ...s, searches: [query, ...s.searches.filter((x) => x.toLowerCase() !== query.toLowerCase())].slice(0, 12) }));
  },
  clearSearches() {
    set((s) => ({ ...s, searches: [] }));
  },
  updateSettings(patch: Partial<Settings>) {
    set((s) => ({ ...s, settings: { ...s.settings, ...patch } }));
  },
  toggleService(id: number) {
    set((s) => {
      const has = s.settings.services.includes(id);
      return { ...s, settings: { ...s.settings, services: has ? s.settings.services.filter((x) => x !== id) : [...s.settings.services, id] } };
    });
  },
  exportJSON(): string {
    return JSON.stringify(getState(), null, 2);
  },
  importJSON(json: string) {
    const parsed = JSON.parse(json) as State;
    if (parsed?.version !== 1 || !parsed.lists) throw new Error("This file isn't a WatchGuide backup.");
    set({ ...initial, ...parsed, settings: { ...initial.settings, ...parsed.settings } });
  },
  reset() {
    set(initial);
  },
};

export function listsContaining(s: State, key: string): ListId[] {
  return (Object.keys(s.lists) as ListId[]).filter((l) => s.lists[l].some((i) => i.key === key));
}

export function watchedEpisodes(s: State, showId: number): string[] {
  return s.episodes[String(showId)] ?? [];
}

export const isMediaType = (t: string): t is MediaType => t === "movie" || t === "tv";

const noopSubscribe = () => () => {};

function localISODate(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}

/**
 * Today's local date (YYYY-MM-DD), or null while prerendering and hydrating.
 * Pages must not read the clock during prerender, so date-dependent UI waits for this.
 */
export function useToday(): string | null {
  return useSyncExternalStore(noopSubscribe, localISODate, () => null);
}

/** Shift a YYYY-MM-DD date by whole days. Pure, so it's safe anywhere. */
export function addDays(iso: string, days: number): string {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}

/** Midnight at the start of a local YYYY-MM-DD date, in ms. */
export function startOfDay(iso: string): number {
  return new Date(`${iso}T00:00:00`).getTime();
}
