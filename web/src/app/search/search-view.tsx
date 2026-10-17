"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { Clock, Search, TrendingUp, X } from "lucide-react";
import { PersonCard, PosterGrid, PosterGridSkeleton } from "@/components/cards";
import { useApi } from "@/lib/api";
import { MOVIE_GENRES, TV_GENRES } from "@/lib/catalog";
import { titleOf } from "@/lib/media";
import { actions, useHydrated, useStore } from "@/lib/store";
import type { MediaItem, Paged } from "@/lib/types";

type Filter = "all" | "movie" | "tv" | "person";
const FILTERS: { id: Filter; label: string }[] = [
  { id: "all", label: "All" },
  { id: "movie", label: "Films" },
  { id: "tv", label: "Shows" },
  { id: "person", label: "People" },
];

export function SearchView() {
  const params = useSearchParams();
  const router = useRouter();
  const q = params.get("q") ?? "";
  const filter = (params.get("type") as Filter) || "all";
  const [text, setText] = useState(q);
  const input = useRef<HTMLInputElement>(null);
  const hydrated = useHydrated();
  const searches = useStore((s) => s.searches);

  // Debounce typing into the URL so results are shareable and Back works.
  useEffect(() => {
    if (text === q) return;
    const t = setTimeout(() => {
      const next = new URLSearchParams(params);
      if (text.trim()) next.set("q", text.trim());
      else next.delete("q");
      router.replace(`/search${next.size ? `?${next}` : ""}`, { scroll: false });
    }, 300);
    return () => clearTimeout(t);
  }, [text, q, params, router]);

  useEffect(() => {
    if (!q) input.current?.focus();
  }, [q]);

  const path = q ? (filter === "all" ? "search/multi" : `search/${filter}`) : null;
  const { data, loading } = useApi<Paged<MediaItem & { profile_path?: string; known_for_department?: string }>>(path, { query: q, include_adult: "false" });
  const trending = useApi<Paged<MediaItem>>(q ? null : "trending/all/day");

  useEffect(() => {
    if (q && data?.results.length) actions.rememberSearch(q);
  }, [q, data]);

  const setFilter = (f: Filter) => {
    const next = new URLSearchParams(params);
    if (f === "all") next.delete("type");
    else next.set("type", f);
    router.replace(`/search?${next}`, { scroll: false });
  };

  const results = data?.results ?? [];
  const people = results.filter((r) => r.media_type === "person" || filter === "person");
  const titles = results.filter((r) => r.media_type !== "person" && filter !== "person" && r.poster_path);

  return (
    <div className="px-4 pt-14 sm:px-8 md:pt-24">
      <h1 className="large-title mb-4">Search</h1>

      <form
        role="search"
        onSubmit={(e) => {
          e.preventDefault();
          input.current?.blur();
        }}
        className="relative max-w-2xl"
      >
        <Search className="pointer-events-none absolute top-1/2 left-4 size-5 -translate-y-1/2 text-faint" />
        <input
          ref={input}
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="Films, shows, people…"
          aria-label="Search films, shows and people"
          className="w-full rounded-full bg-surface py-3 pr-12 pl-12 text-[17px] outline-none transition placeholder:text-faint focus:ring-2 focus:ring-tint"
          type="search"
          enterKeyHint="search"
        />
        {text && (
          <button type="button" aria-label="Clear search" onClick={() => setText("")} className="absolute top-1/2 right-3 grid size-7 -translate-y-1/2 place-items-center rounded-full bg-raised text-muted hover:text-text">
            <X className="size-4" />
          </button>
        )}
      </form>

      <div className="mt-4 flex gap-2" role="tablist" aria-label="Result type">
        {FILTERS.map((f) => (
          <button
            key={f.id}
            type="button"
            role="tab"
            aria-selected={filter === f.id}
            onClick={() => setFilter(f.id)}
            className={`rounded-full px-4 py-1.5 text-sm font-medium transition ${filter === f.id ? "bg-tint text-white" : "bg-surface text-text"}`}
          >
            {f.label}
          </button>
        ))}
      </div>

      <div className="mt-8 pb-8">
        {!q ? (
          <div className="grid gap-10 lg:grid-cols-2">
            {hydrated && searches.length > 0 && (
              <section>
                <div className="mb-3 flex items-center justify-between">
                  <h2 className="flex items-center gap-2 font-semibold"><Clock className="size-4 text-accent" /> Recent</h2>
                  <button type="button" onClick={actions.clearSearches} className="text-sm text-muted hover:text-text">Clear</button>
                </div>
                <div className="flex flex-wrap gap-2">
                  {searches.map((s) => (
                    <button key={s} type="button" onClick={() => setText(s)} className="rounded-full bg-surface px-3.5 py-1.5 text-sm ring-1 ring-line hover:ring-accent">
                      {s}
                    </button>
                  ))}
                </div>
              </section>
            )}
            <section>
              <h2 className="mb-3 flex items-center gap-2 font-semibold"><TrendingUp className="size-4 text-accent" /> Trending searches</h2>
              <ol className="space-y-1">
                {(trending.data?.results ?? []).filter((t) => t.media_type !== "person").slice(0, 8).map((t, i) => (
                  <li key={t.id}>
                    <button type="button" onClick={() => setText(titleOf(t))} className="flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left hover:bg-surface">
                      <span className="w-5 text-right font-display font-bold text-accent tabular-nums">{i + 1}</span>
                      {titleOf(t)}
                    </button>
                  </li>
                ))}
              </ol>
            </section>
            <section className="lg:col-span-2">
              <h2 className="mb-3 font-semibold">Browse by genre</h2>
              <div className="grid grid-cols-2 gap-2.5 sm:grid-cols-3 lg:grid-cols-6">
                {Object.entries(MOVIE_GENRES).filter(([id]) => id !== "10770").map(([id, name]) => (
                  <Link key={id} href={`/discover?genre=${id}&type=movie`} className="rounded-card bg-surface px-4 py-4 text-sm font-semibold ring-1 ring-line transition hover:ring-accent">
                    {name}
                  </Link>
                ))}
                {[10759, 10765, 10764, 10762].map((id) => (
                  <Link key={id} href={`/discover?genre=${id}&type=tv`} className="rounded-card bg-surface px-4 py-4 text-sm font-semibold ring-1 ring-line transition hover:ring-accent">
                    {TV_GENRES[id]} <span className="text-xs font-normal text-muted">TV</span>
                  </Link>
                ))}
              </div>
            </section>
          </div>
        ) : loading ? (
          <PosterGridSkeleton />
        ) : !results.length ? (
          <p className="py-16 text-center text-muted">Nothing found for &ldquo;{q}&rdquo;. Try a different spelling.</p>
        ) : (
          <div className="space-y-10">
            {people.length > 0 && (
              <section>
                {filter === "all" && <h2 className="mb-4 font-semibold">People</h2>}
                <div className="flex flex-wrap gap-5">
                  {people.slice(0, filter === "person" ? 40 : 8).map((p) => (
                    <PersonCard key={p.id} id={p.id} name={titleOf(p)} role={p.known_for_department} path={p.profile_path} />
                  ))}
                </div>
              </section>
            )}
            {titles.length > 0 && (
              <section>
                {filter === "all" && people.length > 0 && <h2 className="mb-4 font-semibold">Titles</h2>}
                <PosterGrid items={titles} type={filter === "movie" || filter === "tv" ? filter : undefined} />
              </section>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
