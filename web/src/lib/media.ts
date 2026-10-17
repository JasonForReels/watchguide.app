import type { MediaItem, MediaType, SavedItem, TitleDetails, Video } from "./types";

const IMAGE_BASE = "https://image.tmdb.org/t/p";

export type ImageSize = "w92" | "w185" | "w300" | "w342" | "w500" | "w780" | "w1280" | "original" | "h632";

export function img(path: string | null | undefined, size: ImageSize = "w342"): string | null {
  return path ? `${IMAGE_BASE}/${size}${path}` : null;
}

export function titleOf(item: { title?: string; name?: string }): string {
  return item.title ?? item.name ?? "Untitled";
}

export function dateOf(item: { release_date?: string; first_air_date?: string }): string | undefined {
  return item.release_date || item.first_air_date || undefined;
}

export function yearOf(item: { release_date?: string; first_air_date?: string }): string | null {
  const d = dateOf(item);
  return d ? d.slice(0, 4) : null;
}

/** TMDB omits `media_type` on typed endpoints, so fall back to the shape of the item. */
export function typeOf(item: MediaItem, fallback?: MediaType): MediaType {
  if (item.media_type === "movie" || item.media_type === "tv") return item.media_type;
  if (fallback) return fallback;
  return item.title !== undefined || item.release_date !== undefined ? "movie" : "tv";
}

export function keyOf(type: MediaType, id: number): string {
  return `${type}-${id}`;
}

export function hrefOf(type: MediaType, id: number): string {
  return `/title/${type}/${id}`;
}

export function toSaved(item: MediaItem | TitleDetails, type: MediaType): SavedItem {
  const genres =
    "genre_ids" in item && item.genre_ids
      ? item.genre_ids
      : "genres" in item && item.genres
        ? item.genres.map((g) => g.id)
        : [];
  return {
    key: keyOf(type, item.id),
    id: item.id,
    type,
    title: titleOf(item),
    poster: item.poster_path ?? null,
    backdrop: item.backdrop_path ?? null,
    year: yearOf(item),
    date: dateOf(item) ?? null,
    rating: item.vote_average ?? null,
    overview: item.overview ?? null,
    genres,
    // Stamped by the store when saved; server code must not read the clock.
    addedAt: 0,
  };
}

/** Turn a saved item back into a list item so the same cards can render it. */
export function fromSaved(s: SavedItem): MediaItem {
  return {
    id: s.id,
    media_type: s.type,
    ...(s.type === "movie" ? { title: s.title, release_date: s.date ?? undefined } : { name: s.title, first_air_date: s.date ?? undefined }),
    poster_path: s.poster,
    backdrop_path: s.backdrop,
    overview: s.overview ?? undefined,
    vote_average: s.rating ?? undefined,
    genre_ids: s.genres,
  };
}

export function runtimeLabel(minutes?: number | null): string | null {
  if (!minutes) return null;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  return h ? `${h}h ${m}m` : `${m}m`;
}

export function formatDate(d?: string | null, opts: Intl.DateTimeFormatOptions = { day: "numeric", month: "short", year: "numeric" }): string {
  if (!d) return "TBA";
  const date = new Date(`${d}T00:00:00`);
  return Number.isNaN(date.getTime()) ? d : date.toLocaleDateString(undefined, opts);
}

export function hasArt(item: MediaItem): boolean {
  return Boolean(item.poster_path);
}

export function dedupe(items: MediaItem[], fallback?: MediaType): MediaItem[] {
  const seen = new Set<string>();
  return items.filter((i) => {
    if (i.media_type === "person") return false;
    const k = keyOf(typeOf(i, fallback), i.id);
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });
}

/** Best YouTube trailer: official trailer, any trailer, teaser, then anything. */
export function pickTrailer(videos: Video[] = []): Video | undefined {
  const yt = videos.filter((v) => v.site === "YouTube");
  return (
    yt.find((v) => v.type === "Trailer" && v.official) ??
    yt.find((v) => v.type === "Trailer") ??
    yt.find((v) => v.type === "Teaser") ??
    yt[0]
  );
}
