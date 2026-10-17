"use client";

import Link from "next/link";
import { useMemo } from "react";
import { genreName } from "@/lib/catalog";
import { useApi } from "@/lib/api";
import { fromSaved, hrefOf, img, keyOf, titleOf, typeOf, yearOf } from "@/lib/media";
import { useHydrated, useStore } from "@/lib/store";
import type { MediaItem, MediaType, Paged } from "@/lib/types";
import { PosterCard } from "./cards";
import { SaveButton } from "./list-buttons";
import { Rail, RailSkeleton } from "./rail";

/** Top 10 with oversized solid rank numerals behind each poster, as on iOS. */
export function RankedRail({ title, items }: { title: string; items: MediaItem[] }) {
  return (
    <Rail title={title} gap="gap-3">
      {items.slice(0, 10).map((item, i) => (
        <div key={item.id} className="flex shrink-0 items-end">
          <span
            className="-mr-5 mb-8 select-none font-display text-[120px] leading-[0.8] font-black tracking-tighter text-text/15 sm:text-[150px]"
            aria-hidden="true"
          >
            {i + 1}
          </span>
          <PosterCard item={item} width="relative w-40 sm:w-48" />
        </div>
      ))}
    </Rail>
  );
}

/** Full-bleed feature card that breaks up the run of poster rows. */
export function Spotlight({ item, eyebrow }: { item: MediaItem; eyebrow: string }) {
  const type = typeOf(item);
  const genres = (item.genre_ids ?? []).slice(0, 2).map(genreName).filter(Boolean);
  return (
    <section className="px-4 sm:px-8">
      <div className="frame relative overflow-hidden rounded-[calc(var(--radius)*1.6)] bg-surface">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={img(item.backdrop_path, "w1280") ?? ""} alt="" loading="lazy" className="absolute inset-0 h-full w-full object-cover" />
        <div className="absolute inset-0 bg-gradient-to-r from-black/90 via-black/60 to-black/10" />
        <div className="relative flex min-h-[320px] flex-col justify-end gap-3 p-6 sm:min-h-[380px] sm:max-w-[60%] sm:p-10">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-accent">{eyebrow}</p>
          <h3 className="font-display text-3xl font-bold tracking-tight text-white sm:text-4xl">{titleOf(item)}</h3>
          <p className="text-sm text-white/70">{[yearOf(item), ...genres].filter(Boolean).join(" · ")}</p>
          <p className="line-clamp-3 text-[15px] leading-relaxed text-white/85">{item.overview}</p>
          <div className="mt-2 flex flex-wrap gap-3">
            <Link href={hrefOf(type, item.id)} className="rounded-full bg-accent px-5 py-2.5 text-sm font-semibold text-on-accent hover:brightness-110">
              Take a look
            </Link>
            <SaveButton item={item} type={type} variant="glass" />
          </div>
        </div>
      </div>
    </section>
  );
}

/** Chapter divider: groups rows so the feed reads in sections, not one endless scroll. */
export function Chapter({ label, title }: { label: string; title: string }) {
  return (
    <div className="px-4 pt-6 sm:px-8">
      <div className="flex items-center gap-4">
        <span className="text-xs font-semibold uppercase tracking-[0.2em] text-accent">{label}</span>
        <span className="h-px flex-1 bg-line" />
      </div>
      <p className="mt-2 font-display text-2xl font-bold tracking-tight sm:text-3xl">{title}</p>
    </div>
  );
}

/** Shows you've started, with the next episode to watch. Client-only: it reads local progress. */
export function UpNextRail() {
  const hydrated = useHydrated();
  const want = useStore((s) => s.lists.want);
  const episodes = useStore((s) => s.episodes);
  const started = useMemo(
    () => want.filter((i) => i.type === "tv" && (episodes[String(i.id)]?.length ?? 0) > 0).slice(0, 12),
    [want, episodes],
  );
  if (!hydrated || !started.length) return null;
  return (
    <Rail title="Up Next" subtitle="Pick up where you left off">
      {started.map((s) => {
        const codes = episodes[String(s.id)] ?? [];
        const last = codes
          .map((c) => c.split("x").map(Number) as [number, number])
          .sort((a, b) => a[0] - b[0] || a[1] - b[1])
          .at(-1);
        return (
          <PosterCard
            key={s.key}
            item={fromSaved(s)}
            caption={last ? `Next: S${last[0]} E${last[1] + 1}` : "Start watching"}
          />
        );
      })}
    </Rail>
  );
}

/** "Because you liked …" built from TMDB recommendations for something on your lists. */
export function BecauseYouLiked() {
  const hydrated = useHydrated();
  const seed = useStore((s) => s.lists.liked[0] ?? s.lists.watched[0] ?? null);
  const saved = useStore((s) => s.lists);
  const { data, loading } = useApi<Paged<MediaItem>>(seed ? `${seed.type}/${seed.id}/recommendations` : null);
  const items = useMemo(() => {
    if (!data || !seed) return [];
    const have = new Set([...saved.watched, ...saved.liked].map((i) => i.key));
    return data.results.filter((i) => i.poster_path && !have.has(keyOf(seed.type, i.id))).slice(0, 16);
  }, [data, seed, saved]);

  if (!hydrated || !seed) return null;
  if (loading) return <RailSkeleton />;
  if (!items.length) return null;
  return (
    <Rail title={`Because you liked ${seed.title}`}>
      {items.map((i) => (
        <PosterCard key={i.id} item={i} type={seed.type as MediaType} />
      ))}
    </Rail>
  );
}

export function WatchlistRail() {
  const hydrated = useHydrated();
  const want = useStore((s) => s.lists.want);
  if (!hydrated || !want.length) return null;
  return (
    <Rail title="Your Watchlist" href="/lists">
      {want.slice(0, 20).map((s) => (
        <PosterCard key={s.key} item={fromSaved(s)} />
      ))}
    </Rail>
  );
}
