"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState } from "react";
import { ArrowLeft } from "lucide-react";
import { PosterGrid, PosterGridSkeleton } from "@/components/cards";
import { PageHeader } from "@/components/rail";
import { api } from "@/lib/api";
import { MOODS, MOVIE_GENRES, TV_GENRES } from "@/lib/catalog";
import { dedupe } from "@/lib/media";
import type { MediaItem, MediaType, Paged } from "@/lib/types";

const SORTS = [
  { id: "popularity.desc", label: "Most popular" },
  { id: "vote_average.desc", label: "Highest rated" },
  { id: "newest", label: "Newest" },
  { id: "oldest", label: "Oldest" },
] as const;

type SortId = (typeof SORTS)[number]["id"];

function sortParams(sort: SortId, type: MediaType) {
  const date = type === "movie" ? "primary_release_date" : "first_air_date";
  if (sort === "newest") return { sort_by: `${date}.desc`, [`${date}.lte`]: new Date().toISOString().slice(0, 10) };
  if (sort === "oldest") return { sort_by: `${date}.asc` };
  return { sort_by: sort };
}

export function DiscoverView() {
  const params = useSearchParams();
  const router = useRouter();
  const moodSlug = params.get("mood");
  const genre = params.get("genre");
  const type = (params.get("type") as MediaType) || "movie";
  const mood = MOODS.find((m) => m.slug === moodSlug);
  const [sort, setSort] = useState<SortId>("popularity.desc");
  const [minRating, setMinRating] = useState(6);
  const [page, setPage] = useState(1);
  const [items, setItems] = useState<MediaItem[]>([]);
  const [loadedKey, setLoadedKey] = useState<string | null>(null);
  const [hasMore, setHasMore] = useState(true);

  const active = Boolean(mood || genre);
  const filterKey = `${moodSlug}|${genre}|${type}|${sort}|${minRating}`;
  const requestKey = `${filterKey}|${page}`;
  const loading = active && loadedKey !== requestKey;

  // Reset paging whenever the filter changes.
  const [lastKey, setLastKey] = useState(filterKey);
  if (lastKey !== filterKey) {
    setLastKey(filterKey);
    setPage(1);
    setItems([]);
    setHasMore(true);
  }

  useEffect(() => {
    if (!active) return;
    let live = true;
    const base = mood ? mood[type] : { with_genres: genre ?? undefined };
    api<Paged<MediaItem>>(`discover/${type}`, {
      ...base,
      ...sortParams(sort, type),
      "vote_average.gte": minRating,
      "vote_count.gte": sort === "vote_average.desc" ? 500 : 80,
      include_adult: "false",
      page,
    })
      .then((r) => {
        if (!live) return;
        setItems((prev) => dedupe([...(page === 1 ? [] : prev), ...r.results.filter((i) => i.poster_path)], type));
        setHasMore(r.page < r.total_pages);
      })
      .finally(() => live && setLoadedKey(requestKey));
    return () => {
      live = false;
    };
  }, [active, mood, genre, type, sort, minRating, page, requestKey]);

  const setParam = (patch: Record<string, string | null>) => {
    const next = new URLSearchParams(params);
    for (const [k, v] of Object.entries(patch)) {
      if (v === null) next.delete(k);
      else next.set(k, v);
    }
    router.push(`/discover${next.size ? `?${next}` : ""}`, { scroll: false });
  };

  if (!active) {
    return (
      <div className="pb-10">
        <PageHeader title="How are you feeling?" subtitle="Pick a mood. We'll find films and shows that fit it." />
        <div className="grid grid-cols-2 gap-3 px-4 sm:grid-cols-3 sm:px-8 lg:grid-cols-4">
          {MOODS.map((m, i) => (
            <button
              key={m.slug}
              type="button"
              onClick={() => setParam({ mood: m.slug, genre: null })}
              className="frame rise group rounded-card border border-line bg-surface p-5 text-left transition hover:-translate-y-0.5 hover:border-accent"
              style={{ animationDelay: `${i * 30}ms` }}
            >
              <span className="text-3xl transition group-hover:scale-110 inline-block">{m.emoji}</span>
              <p className="mt-3 font-display text-lg font-semibold">{m.name}</p>
              <p className="text-sm text-muted">{m.subtitle}</p>
            </button>
          ))}
        </div>
      </div>
    );
  }

  const title = mood ? `${mood.emoji} ${mood.name}` : (type === "movie" ? MOVIE_GENRES : TV_GENRES)[Number(genre)] ?? "Discover";

  return (
    <div className="pb-10">
      <div className="px-4 pt-8 sm:px-8 lg:pt-10">
        <button type="button" onClick={() => router.push("/discover")} className="mb-4 inline-flex items-center gap-1.5 text-sm text-muted hover:text-text">
          <ArrowLeft className="size-4" /> All moods
        </button>
        <h1 className="font-display text-3xl font-bold tracking-tight sm:text-4xl">{title}</h1>
        {mood && <p className="mt-1 text-muted">{mood.subtitle}</p>}
      </div>

      <div className="sticky top-0 z-20 mt-5 mb-6 flex flex-wrap items-center gap-3 border-b border-line bg-bg/85 px-4 py-3 backdrop-blur-xl sm:px-8">
        <div className="flex gap-1 rounded-full bg-surface p-1">
          {(["movie", "tv"] as const).map((t) => (
            <button key={t} type="button" onClick={() => setParam({ type: t, ...(genre ? { genre: null, mood: null } : {}) })} className={`rounded-full px-4 py-1 text-sm transition ${type === t ? "bg-accent font-medium text-on-accent" : "text-muted"}`}>
              {t === "movie" ? "Films" : "Shows"}
            </button>
          ))}
        </div>
        <select value={sort} onChange={(e) => setSort(e.target.value as SortId)} aria-label="Sort" className="rounded-full bg-surface px-3 py-1.5 text-sm ring-1 ring-line outline-none">
          {SORTS.map((s) => <option key={s.id} value={s.id}>{s.label}</option>)}
        </select>
        <label className="flex items-center gap-2.5 text-sm text-muted">
          Min rating
          <input type="range" min={0} max={8.5} step={0.5} value={minRating} onChange={(e) => setMinRating(Number(e.target.value))} className="w-28 accent-[var(--accent)]" />
          <span className="w-7 font-medium text-text tabular-nums">{minRating.toFixed(1)}</span>
        </label>
      </div>

      <div className="px-4 sm:px-8">
        {items.length === 0 && loading ? (
          <PosterGridSkeleton />
        ) : (
          <PosterGrid
            items={items}
            type={type}
            empty={<p className="py-16 text-center text-muted">No results match. Try lowering the minimum rating.</p>}
          />
        )}
        {items.length > 0 && hasMore && (
          <div className="mt-8 text-center">
            <button type="button" disabled={loading} onClick={() => setPage((p) => p + 1)} className="rounded-full bg-surface px-6 py-2.5 text-sm font-semibold ring-1 ring-line hover:ring-accent disabled:opacity-50">
              {loading ? "Loading…" : "Load more"}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
