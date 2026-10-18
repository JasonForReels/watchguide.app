import "server-only";
import type { CollectionDetails, MediaItem, MediaType, Paged, PersonDetails, SeasonDetails, TitleDetails } from "./types";

const BASE = "https://api.themoviedb.org/3";

/** Paths the browser may ask the proxy for. Everything is read-only TMDB data. */
const ALLOWED = [
  /^trending\/(all|movie|tv|person)\/(day|week)$/,
  /^(movie|tv)\/(popular|top_rated|now_playing|upcoming|airing_today|on_the_air)$/,
  /^(movie|tv)\/\d+(\/(recommendations|similar|videos|credits|watch\/providers|images|keywords|release_dates))?$/,
  /^tv\/\d+\/season\/\d+$/,
  /^search\/(multi|movie|tv|person|company|collection)$/,
  /^discover\/(movie|tv)$/,
  /^person\/\d+(\/combined_credits)?$/,
  /^collection\/\d+$/,
  /^genre\/(movie|tv)\/list$/,
  /^watch\/providers\/(movie|tv)$/,
  /^company\/\d+$/,
  /^network\/\d+$/,
];

export function isAllowedPath(path: string): boolean {
  return ALLOWED.some((r) => r.test(path));
}

/**
 * Cached TMDB GET. Arguments form the cache key, so identical requests from
 * any page or the proxy share one entry for an hour.
 */
export async function tmdb<T>(path: string, params: Record<string, string | number | undefined> = {}): Promise<T> {
  const key = process.env.TMDB_API_KEY;
  if (!key) throw new Error("TMDB_API_KEY is not set. Copy .env.example to .env.local and add it.");
  const url = new URL(`${BASE}/${path}`);
  url.searchParams.set("api_key", key);
  url.searchParams.set("language", "en-US");
  for (const [k, v] of Object.entries(params)) {
    if (v !== undefined && v !== "") url.searchParams.set(k, String(v));
  }
  const res = await fetch(url, { next: { revalidate: 86400 } });
  if (!res.ok) throw new Error(`TMDB ${res.status} for ${path}`);
  return res.json() as Promise<T>;
}

/** Same as `tmdb` but resolves to null instead of throwing, for optional sections. */
export async function tmdbSafe<T>(path: string, params?: Record<string, string | number | undefined>): Promise<T | null> {
  try {
    return await tmdb<T>(path, params);
  } catch {
    return null;
  }
}

export const list = (path: string, params?: Record<string, string | number | undefined>) =>
  tmdbSafe<Paged<MediaItem>>(path, params).then((r) => r?.results ?? []);

export function getTitle(type: MediaType, id: number) {
  return tmdb<TitleDetails>(`${type}/${id}`, {
    append_to_response: `credits,videos,recommendations,similar,images,watch/providers,external_ids,${type === "movie" ? "release_dates" : "content_ratings"}`,
    include_image_language: "en,null",
  });
}

export const getSeason = (id: number, season: number) => tmdb<SeasonDetails>(`tv/${id}/season/${season}`);

export const getPerson = (id: number) => tmdb<PersonDetails>(`person/${id}`, { append_to_response: "combined_credits" });

export const getCollection = (id: number) => tmdb<CollectionDetails>(`collection/${id}`);
