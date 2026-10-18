import { list, tmdbSafe } from "@/lib/tmdb";
import type { MediaItem, MediaType } from "@/lib/types";

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10);

/** Movies with a digital or TV release, and series premiering, in the next 60 days (any service). */
export async function comingToStreaming(): Promise<MediaItem[]> {
  const [movies, shows] = await Promise.all([
    list("discover/movie", {
      region: "US",
      with_release_type: "4|6",
      "release_date.gte": day(1),
      "release_date.lte": day(60),
      sort_by: "popularity.desc",
    }),
    list("discover/tv", {
      "first_air_date.gte": day(1),
      "first_air_date.lte": day(60),
      sort_by: "popularity.desc",
    }),
  ]);
  const seen = new Set<number>();
  const merged: MediaItem[] = [];
  for (let i = 0; i < Math.max(movies.length, shows.length); i++) {
    for (const item of [movies[i], shows[i]]) {
      if (item?.poster_path && !seen.has(item.id)) {
        seen.add(item.id);
        merged.push(item);
      }
    }
  }
  return merged.slice(0, 20);
}

export interface LeavingEntry {
  item: MediaItem;
  type: MediaType;
  service: string;
  leavesOn: string;
}

// Same cache the apps read: one list per service and country, kept fresh by scripts/leaving/update.mjs.
const SERVICES: { id: number; name: string }[] = [
  { id: 8, name: "Netflix" },
  { id: 337, name: "Disney+" },
  { id: 9, name: "Prime Video" },
  { id: 384, name: "Max" },
  { id: 350, name: "Apple TV+" },
  { id: 15, name: "Hulu" },
];

interface Listing { title: string; date: string; tmdbId?: number; type?: string }

/** Titles leaving the main US services soon. Empty unless SUPABASE_URL and SUPABASE_ANON_KEY are set. */
export async function leavingSoon(): Promise<LeavingEntry[]> {
  const base = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_ANON_KEY;
  if (!base || !key) return [];

  const now = Date.now();
  const horizon = now + 60 * 86_400_000;
  const found: { listing: Listing; service: string }[] = [];
  await Promise.all(
    SERVICES.map(async ({ id, name }) => {
      try {
        const url = new URL("/rest/v1/api_cache", base);
        url.searchParams.set("cache_key", `eq.leaving:catalog:${id}:us`);
        url.searchParams.set("expires_at", `gt.${new Date().toISOString()}`);
        url.searchParams.set("select", "response_data");
        url.searchParams.set("limit", "1");
        const res = await fetch(url, { headers: { apikey: key, Authorization: `Bearer ${key}` } });
        if (!res.ok) return;
        const rows = (await res.json()) as { response_data?: { listings?: Listing[] } }[];
        for (const l of rows[0]?.response_data?.listings ?? []) {
          const t = Date.parse(l.date);
          if (l.tmdbId && (l.type === "movie" || l.type === "tv") && t > now && t <= horizon) found.push({ listing: l, service: name });
        }
      } catch {
        // A service whose list can't be read is simply skipped.
      }
    }),
  );

  found.sort((a, b) => Date.parse(a.listing.date) - Date.parse(b.listing.date));
  const seen = new Set<number>();
  const entries: LeavingEntry[] = [];
  for (const { listing, service } of found) {
    if (entries.length >= 15) break;
    if (seen.has(listing.tmdbId!)) continue;
    const type = listing.type as MediaType;
    const item = await tmdbSafe<MediaItem>(`${type}/${listing.tmdbId}`);
    if (!item?.backdrop_path) continue;
    seen.add(listing.tmdbId!);
    entries.push({ item: { ...item, media_type: type }, type, service, leavesOn: listing.date });
  }
  return entries;
}
