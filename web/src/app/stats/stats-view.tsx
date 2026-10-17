"use client";

import Link from "next/link";
import { useMemo } from "react";
import { PosterArt } from "@/components/cards";
import { ProGate } from "@/components/pro-gate";
import { PageHeader } from "@/components/rail";
import { genreName } from "@/lib/catalog";
import { hrefOf } from "@/lib/media";
import { startOfDay, useHydrated, useStore, useToday } from "@/lib/store";

function Tile({ label, value, note }: { label: string; value: string | number; note?: string }) {
  return (
    <div className="rounded-card border border-line bg-surface p-5">
      <p className="text-sm text-muted">{label}</p>
      <p className="mt-1 font-display text-4xl font-bold tracking-tight tabular-nums">{value}</p>
      {note && <p className="mt-1 text-xs text-faint">{note}</p>}
    </div>
  );
}

function Card({ title, children, className = "" }: { title: string; children: React.ReactNode; className?: string }) {
  return (
    <section className={`rounded-card border border-line bg-surface p-5 ${className}`}>
      <h2 className="mb-4 font-semibold">{title}</h2>
      {children}
    </section>
  );
}

/** Horizontal bars, one hue. The value is printed beside each bar so colour never carries meaning alone. */
function Bars({ rows }: { rows: { label: string; value: number }[] }) {
  const max = Math.max(1, ...rows.map((r) => r.value));
  return (
    <ul className="space-y-2.5">
      {rows.map((r) => (
        <li key={r.label} className="grid grid-cols-[96px_1fr_32px] items-center gap-3 text-sm" title={`${r.label}: ${r.value}`}>
          <span className="truncate text-muted">{r.label}</span>
          <span className="h-2.5 overflow-hidden rounded-full bg-bg">
            <span className="block h-full rounded-full bg-accent" style={{ width: `${(r.value / max) * 100}%` }} />
          </span>
          <span className="text-right tabular-nums">{r.value}</span>
        </li>
      ))}
    </ul>
  );
}

const DAY = 864e5;

export function StatsView() {
  const hydrated = useHydrated();
  const s = useStore((st) => st);
  const todayISO = useToday();

  const stats = useMemo(() => {
    const films = s.lists.watched.filter((i) => i.type === "movie");
    const shows = s.lists.watched.filter((i) => i.type === "tv");
    const episodes = Object.values(s.episodes).reduce((a, e) => a + e.length, 0);
    const minutes = s.log.reduce((a, e) => a + e.minutes, 0);
    const all = [...s.lists.watched, ...s.lists.liked];
    const seen = new Set<string>();
    const unique = all.filter((i) => !seen.has(i.key) && seen.add(i.key));

    const genreCount = new Map<string, number>();
    for (const i of unique) for (const g of i.genres) {
      const n = genreName(g);
      if (n) genreCount.set(n, (genreCount.get(n) ?? 0) + 1);
    }
    const genres = [...genreCount].sort((a, b) => b[1] - a[1]).slice(0, 8).map(([label, value]) => ({ label, value }));

    const decadeCount = new Map<string, number>();
    for (const i of unique) if (i.year) {
      const d = `${i.year.slice(0, 3)}0s`;
      decadeCount.set(d, (decadeCount.get(d) ?? 0) + 1);
    }
    const decades = [...decadeCount].sort((a, b) => a[0].localeCompare(b[0])).map(([label, value]) => ({ label, value }));

    const ratings = [5, 4, 3, 2, 1].map((n) => ({ label: "★".repeat(n), value: Object.values(s.ratings).filter((r) => r === n).length }));

    // 26-week activity grid, Monday-first, from the watch log.
    const today = new Date(todayISO ? startOfDay(todayISO) : 0);
    const start = new Date(today.getTime() - (7 * 25 + ((today.getDay() + 6) % 7)) * DAY);
    const perDay = new Map<number, number>();
    for (const e of s.log) {
      const d = new Date(e.at);
      d.setHours(0, 0, 0, 0);
      if (d >= start) perDay.set(d.getTime(), (perDay.get(d.getTime()) ?? 0) + 1);
    }
    const weeks = Array.from({ length: 26 }, (_, w) =>
      Array.from({ length: 7 }, (_, d) => {
        const t = start.getTime() + (w * 7 + d) * DAY;
        return { t, n: t > today.getTime() ? -1 : perDay.get(t) ?? 0 };
      }),
    );

    const rated = Object.entries(s.ratings).sort((a, b) => b[1] - a[1]).map(([k]) => unique.find((i) => i.key === k) ?? s.lists.want.find((i) => i.key === k)).filter(Boolean).slice(0, 8);

    return { films, shows, episodes, minutes, genres, decades, ratings, weeks, rated };
  }, [s, todayISO]);

  if (!hydrated || !todayISO) return <div className="px-8 pt-10"><div className="skeleton h-40 rounded-card" /></div>;

  const empty = !s.lists.watched.length && !stats.episodes;
  const level = (n: number) => (n <= 0 ? 0 : n === 1 ? 0.35 : n <= 3 ? 0.65 : 1);
  const tvShare = stats.films.length + stats.episodes ? Math.round((stats.episodes / (stats.films.length + stats.episodes)) * 100) : 0;

  return (
    <div className="pb-10">
      <PageHeader title="Your Stats" subtitle="Built from what you've marked as watched in this browser." />
      <ProGate feature="Stats & insights">
      {empty ? (
        <div className="mx-auto max-w-sm py-12 text-center">
          <p className="font-display text-xl font-semibold">Nothing to count yet</p>
          <p className="mt-1.5 text-sm text-muted">Mark a film as watched or tick off a few episodes, and your stats start here.</p>
          <Link href="/tonight" className="mt-5 inline-block rounded-full bg-accent px-5 py-2.5 text-sm font-semibold text-on-accent">Open Tonight</Link>
        </div>
      ) : (
        <div className="space-y-4 px-4 sm:px-8">
          <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
            <Tile label="Films watched" value={stats.films.length} />
            <Tile label="Episodes watched" value={stats.episodes} note={`${stats.shows.length} show${stats.shows.length === 1 ? "" : "s"} finished`} />
            <Tile label="Hours watched" value={Math.round(stats.minutes / 60)} note="Estimated from runtimes" />
            <Tile label="On your watchlist" value={s.lists.want.length} />
          </div>

          <Card title="Activity, last 6 months">
            <div className="overflow-x-auto">
              <div className="inline-grid grid-flow-col gap-1" style={{ gridTemplateRows: "repeat(7, 12px)" }}>
                {stats.weeks.flat().map((c) => (
                  <span
                    key={c.t}
                    title={c.n >= 0 ? `${new Date(c.t).toLocaleDateString(undefined, { day: "numeric", month: "short" })}: ${c.n} watched` : undefined}
                    className="size-3 rounded-[3px]"
                    style={{ background: c.n < 0 ? "transparent" : c.n === 0 ? "var(--color-line)" : `color-mix(in oklab, var(--accent) ${level(c.n) * 100}%, var(--surface))` }}
                  />
                ))}
              </div>
            </div>
            <p className="mt-3 flex items-center gap-2 text-xs text-faint">
              Less
              {[0, 0.35, 0.65, 1].map((l) => <span key={l} className="size-3 rounded-[3px]" style={{ background: l ? `color-mix(in oklab, var(--accent) ${l * 100}%, var(--surface))` : "var(--color-line)" }} />)}
              More
            </p>
          </Card>

          <div className="grid gap-4 lg:grid-cols-2">
            <Card title="Films vs shows">
              <div className="flex h-3 gap-0.5 overflow-hidden rounded-full">
                <span className="bg-accent" style={{ width: `${100 - tvShare}%` }} />
                <span className="bg-secondary" style={{ width: `${tvShare}%` }} />
              </div>
              <div className="mt-3 flex justify-between text-sm">
                <span className="flex items-center gap-2"><span className="size-2.5 rounded-full bg-accent" /> Films · {stats.films.length}</span>
                <span className="flex items-center gap-2"><span className="size-2.5 rounded-full bg-secondary" /> Episodes · {stats.episodes}</span>
              </div>
            </Card>
            <Card title="Your ratings">
              <Bars rows={stats.ratings} />
            </Card>
            {stats.genres.length > 0 && <Card title="Top genres"><Bars rows={stats.genres} /></Card>}
            {stats.decades.length > 0 && <Card title="By decade"><Bars rows={stats.decades} /></Card>}
          </div>

          {stats.rated.length > 0 && (
            <Card title="Your highest rated">
              <div className="rail -m-1 flex gap-3 overflow-x-auto p-1">
                {stats.rated.map((i) => (
                  <Link key={i!.key} href={hrefOf(i!.type, i!.id)} className="w-24 shrink-0">
                    <div className="frame aspect-[2/3] overflow-hidden rounded-[calc(var(--radius)*0.6)]"><PosterArt path={i!.poster} alt={i!.title} size="w185" /></div>
                    <p className="mt-1.5 truncate text-xs">{i!.title}</p>
                    <p className="text-xs text-accent">{"★".repeat(s.ratings[i!.key])}</p>
                  </Link>
                ))}
              </div>
            </Card>
          )}
        </div>
      )}
      </ProGate>
    </div>
  );
}
