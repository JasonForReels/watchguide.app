"use client";

import Link from "next/link";
import { useEffect, useMemo, useState } from "react";
import { PosterArt } from "@/components/cards";
import { PageHeader } from "@/components/rail";
import { api } from "@/lib/api";
import { hrefOf, keyOf, titleOf } from "@/lib/media";
import { addDays, startOfDay, useHydrated, useStore, useToday } from "@/lib/store";
import type { MediaItem, MediaType, Paged, TitleDetails } from "@/lib/types";

interface Entry {
  key: string;
  id: number;
  type: MediaType;
  title: string;
  poster: string | null;
  date: string;
  detail: string;
  mine: boolean;
}

type Scope = "mine" | "all";

function countdown(date: string, today: string): string {
  const days = Math.round((startOfDay(date) - startOfDay(today)) / 864e5);
  if (days <= 0) return "Today";
  if (days === 1) return "Tomorrow";
  if (days < 7) return `In ${days} days`;
  if (days < 14) return "Next week";
  return `In ${Math.round(days / 7)} weeks`;
}

export function CalendarView() {
  const hydrated = useHydrated();
  const today = useToday();
  const want = useStore((s) => s.lists.want);
  const watchedShows = useStore((s) => s.episodes);
  const region = useStore((s) => s.settings.region);
  const [scope, setScope] = useState<Scope>("all");
  const [entries, setEntries] = useState<Entry[] | null>(null);

  const tracked = useMemo(() => {
    const ids = new Set(want.filter((i) => i.type === "tv").map((i) => i.id));
    Object.keys(watchedShows).forEach((id) => ids.add(Number(id)));
    return [...ids].slice(0, 30);
  }, [want, watchedShows]);
  const savedKeys = useMemo(() => new Set(want.map((i) => i.key)), [want]);

  useEffect(() => {
    if (!hydrated || !today) return;
    let live = true;
    const end = addDays(today, 120);

    const shows = Promise.all(
      tracked.map((id) =>
        api<TitleDetails>(`tv/${id}`)
          .then((d): Entry | null => {
            const ep = d.next_episode_to_air;
            if (!ep?.air_date) return null;
            return { key: keyOf("tv", d.id), id: d.id, type: "tv", title: titleOf(d), poster: d.poster_path ?? null, date: ep.air_date, detail: `S${ep.season_number} E${ep.episode_number} · ${ep.name}`, mine: true };
          })
          .catch(() => null),
      ),
    );
    const movies = Promise.all([1, 2].map((page) =>
      api<Paged<MediaItem>>("discover/movie", { region, "primary_release_date.gte": today, "primary_release_date.lte": end, sort_by: "popularity.desc", with_release_type: "2|3|4", page }),
    )).then((pages) => pages.flatMap((p) => p.results));
    const premieres = api<Paged<MediaItem>>("discover/tv", { "first_air_date.gte": today, "first_air_date.lte": end, sort_by: "popularity.desc", "with_original_language": "en" }).then((p) => p.results);

    Promise.all([shows, movies, premieres]).then(([s, m, p]) => {
      if (!live) return;
      const out: Entry[] = s.filter((e): e is Entry => Boolean(e));
      for (const i of m) if (i.release_date && i.poster_path) out.push({ key: keyOf("movie", i.id), id: i.id, type: "movie", title: titleOf(i), poster: i.poster_path, date: i.release_date, detail: "In cinemas", mine: savedKeys.has(keyOf("movie", i.id)) });
      for (const i of p) if (i.first_air_date && i.poster_path) out.push({ key: keyOf("tv", i.id), id: i.id, type: "tv", title: titleOf(i), poster: i.poster_path, date: i.first_air_date, detail: "Series premiere", mine: savedKeys.has(keyOf("tv", i.id)) });
      const seen = new Set<string>();
      setEntries(out.filter((e) => e.date >= today && !seen.has(e.key) && seen.add(e.key)).sort((a, b) => a.date.localeCompare(b.date)));
    });
    return () => {
      live = false;
    };
  }, [hydrated, today, tracked, region, savedKeys]);

  const shown = (entries ?? []).filter((e) => scope === "all" || e.mine);
  const groups = useMemo(() => {
    const map = new Map<string, Entry[]>();
    for (const e of shown) map.set(e.date, [...(map.get(e.date) ?? []), e]);
    return [...map.entries()];
  }, [shown]);

  return (
    <div className="pb-10">
      <PageHeader title="Calendar" subtitle="New episodes of your shows, and what's coming to cinemas.">
        <div className="flex gap-1 rounded-full bg-surface p-1">
          {(["all", "mine"] as const).map((s) => (
            <button key={s} type="button" onClick={() => setScope(s)} className={`rounded-full px-4 py-1.5 text-sm transition ${scope === s ? "bg-accent font-medium text-on-accent" : "text-muted"}`}>
              {s === "all" ? "Everything" : "Just mine"}
            </button>
          ))}
        </div>
      </PageHeader>

      <div className="px-4 sm:px-8">
        {!entries ? (
          <div className="space-y-3">{Array.from({ length: 5 }, (_, i) => <div key={i} className="skeleton h-24 rounded-card" />)}</div>
        ) : !groups.length ? (
          <p className="py-16 text-center text-muted">
            {scope === "mine" ? "Nothing coming up from your lists. Save some upcoming titles or track a show." : "Nothing scheduled."}
          </p>
        ) : (
          <ol className="space-y-8">
            {groups.map(([date, list]) => (
              <li key={date} className="grid gap-3 sm:grid-cols-[140px_1fr]">
                <div className="sm:sticky sm:top-4 sm:self-start">
                  <p className="font-display text-lg font-semibold">{new Date(`${date}T00:00:00`).toLocaleDateString(undefined, { weekday: "short", day: "numeric", month: "short" })}</p>
                  <p className="text-sm font-medium text-accent">{today && countdown(date, today)}</p>
                </div>
                <ul className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
                  {list.map((e) => (
                    <li key={e.key}>
                      <Link href={hrefOf(e.type, e.id)} className={`flex gap-3 rounded-card bg-surface p-2.5 transition hover:bg-raised ${e.mine ? "ring-1 ring-accent/60" : ""}`}>
                        <div className="frame aspect-[2/3] w-14 shrink-0 overflow-hidden rounded-[calc(var(--radius)*0.5)]">
                          <PosterArt path={e.poster} alt={e.title} size="w185" />
                        </div>
                        <div className="min-w-0 py-0.5">
                          <p className="truncate font-medium">{e.title}</p>
                          <p className="line-clamp-2 text-sm text-muted">{e.detail}</p>
                          {e.mine && <p className="mt-1 text-[11px] font-semibold uppercase tracking-wider text-accent">On your list</p>}
                        </div>
                      </Link>
                    </li>
                  ))}
                </ul>
              </li>
            ))}
          </ol>
        )}
      </div>
    </div>
  );
}
