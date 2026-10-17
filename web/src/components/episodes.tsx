"use client";

import { useMemo, useState } from "react";
import { Check, TrendingUp } from "lucide-react";
import { formatDate, img, runtimeLabel } from "@/lib/media";
import { actions, useStore, useToday } from "@/lib/store";
import type { Episode, SavedItem, SeasonDetails } from "@/lib/types";

/** Before hydration `today` is null and nothing counts as aired yet. */
const aired = (e: Episode, today: string | null) => Boolean(today && e.air_date && e.air_date <= today);
const code = (e: Episode) => `${e.season_number}x${e.episode_number}`;

interface Point {
  ep: Episode;
  index: number;
  rating: number;
}

/**
 * Finds where a show "gets good": the first episode after the early dip whose
 * three-episode rolling average reaches the show's upper quartile.
 */
function analyse(points: Point[]) {
  if (points.length < 5) return null;
  const roll = points.map((_, i) => {
    const w = points.slice(i, i + 3);
    return w.reduce((a, p) => a + p.rating, 0) / w.length;
  });
  const sorted = [...points.map((p) => p.rating)].sort((a, b) => a - b);
  const q3 = sorted[Math.floor(sorted.length * 0.75)];
  const start = roll[0];
  const early = Math.max(3, Math.floor(points.length * 0.5));
  let valley = 0;
  for (let i = 1; i < early; i++) if (roll[i] < roll[valley]) valley = i;
  const payoff = roll.findIndex((r, i) => i > valley && r >= q3 && r > start + 0.15);
  const startsStrong = start >= q3 - 0.05;
  return { valley, payoff: payoff === -1 ? null : payoff, startsStrong, q3 };
}

function PayoffCurve({ seasons, watched, today }: { seasons: SeasonDetails[]; watched: Set<string>; today: string | null }) {
  const points = useMemo<Point[]>(
    () =>
      seasons
        .flatMap((s) => s.episodes)
        .filter((e) => aired(e, today) && (e.vote_count ?? 0) > 0 && (e.vote_average ?? 0) > 0)
        .map((ep, index) => ({ ep, index, rating: ep.vote_average! })),
    [seasons, today],
  );
  const result = useMemo(() => analyse(points), [points]);
  if (!result) return null;

  const W = 720;
  const H = 180;
  const pad = 24;
  const min = Math.max(0, Math.min(...points.map((p) => p.rating)) - 0.5);
  const max = Math.min(10, Math.max(...points.map((p) => p.rating)) + 0.3);
  const x = (i: number) => pad + (i / Math.max(1, points.length - 1)) * (W - pad * 2);
  const y = (r: number) => H - pad - ((r - min) / (max - min || 1)) * (H - pad * 2);
  const path = points.map((p, i) => `${i ? "L" : "M"}${x(i).toFixed(1)},${y(p.rating).toFixed(1)}`).join("");
  const area = `${path}L${x(points.length - 1)},${H - pad}L${x(0)},${H - pad}Z`;
  const lastWatched = points.reduce((acc, p, i) => (watched.has(code(p.ep)) ? i : acc), -1);
  const payoff = result.payoff !== null ? points[result.payoff] : null;

  let minutesToPayoff: number | null = null;
  if (payoff && lastWatched < result.payoff!) {
    minutesToPayoff = points
      .slice(lastWatched + 1, result.payoff! + 1)
      .reduce((a, p) => a + (p.ep.runtime ?? 45), 0);
  }

  let verdict: string;
  if (result.startsStrong) verdict = "Starts strong and stays there. No warm-up needed.";
  else if (payoff && minutesToPayoff) verdict = `It gets good at S${payoff.ep.season_number} E${payoff.ep.episode_number}. That's ${runtimeLabel(minutesToPayoff)} from where you are.`;
  else if (payoff) verdict = `It gets good at S${payoff.ep.season_number} E${payoff.ep.episode_number}, and you're past it.`;
  else verdict = "It doesn't really climb. If the first episodes didn't grab you, it's fine to stop.";

  return (
    <div className="rounded-card border border-line bg-surface p-4 sm:p-5">
      <div className="mb-3 flex items-start gap-3">
        <span className="grid size-9 shrink-0 place-items-center rounded-full bg-accent/15 text-accent">
          <TrendingUp className="size-4.5" />
        </span>
        <div>
          <h3 className="font-semibold">Payoff curve</h3>
          <p className="text-sm text-muted">{verdict}</p>
        </div>
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} className="h-auto w-full" role="img" aria-label="Episode ratings across the series">
        <defs>
          <linearGradient id="payoff-fill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="var(--accent)" stopOpacity="0.35" />
            <stop offset="1" stopColor="var(--accent)" stopOpacity="0" />
          </linearGradient>
        </defs>
        {!result.startsStrong && result.payoff !== null && (
          <rect x={x(0)} y={pad / 2} width={Math.max(0, x(result.payoff) - x(0))} height={H - pad * 1.5} fill="var(--text)" opacity="0.04" />
        )}
        <path d={area} fill="url(#payoff-fill)" />
        <path d={path} fill="none" stroke="var(--accent)" strokeWidth="2.2" strokeLinejoin="round" strokeLinecap="round" />
        {lastWatched >= 0 && (
          <g>
            <line x1={x(lastWatched)} x2={x(lastWatched)} y1={pad / 2} y2={H - pad} stroke="var(--text)" strokeDasharray="3 4" opacity="0.5" />
            <text x={x(lastWatched)} y={pad / 2 + 2} textAnchor="middle" fontSize="11" fill="var(--text)" opacity="0.8">You</text>
          </g>
        )}
        {payoff && !result.startsStrong && (
          <g>
            <circle cx={x(result.payoff!)} cy={y(payoff.rating)} r="6" fill="var(--bg)" stroke="var(--accent)" strokeWidth="2.5" />
            <text x={x(result.payoff!)} y={y(payoff.rating) - 12} textAnchor="middle" fontSize="11" fontWeight="600" fill="var(--accent)">
              Gets good
            </text>
          </g>
        )}
        {seasons.length > 1 &&
          seasons.slice(1).map((s) => {
            const i = points.findIndex((p) => p.ep.season_number === s.season_number);
            if (i <= 0) return null;
            return (
              <text key={s.season_number} x={x(i)} y={H - 6} fontSize="10" fill="var(--text)" opacity="0.45" textAnchor="middle">
                S{s.season_number}
              </text>
            );
          })}
      </svg>
      <p className="mt-1 text-xs text-faint">Episode ratings from TMDB voters.</p>
    </div>
  );
}

export function SeasonTracker({ show, seasons }: { show: SavedItem; seasons: SeasonDetails[] }) {
  const [active, setActive] = useState(seasons[0]?.season_number ?? 1);
  const today = useToday();
  const watchedList = useStore((s) => s.episodes[String(show.id)]);
  const watched = useMemo(() => new Set(watchedList ?? []), [watchedList]);
  const season = seasons.find((s) => s.season_number === active) ?? seasons[0];
  if (!season) return null;

  const all = seasons.flatMap((s) => s.episodes).filter((e) => aired(e, today));
  const done = all.filter((e) => watched.has(code(e))).length;
  const pct = all.length ? Math.round((done / all.length) * 100) : 0;
  const airedHere = season.episodes.filter((e) => aired(e, today));
  const seasonDone = airedHere.length > 0 && airedHere.every((e) => watched.has(code(e)));
  const remaining = all.filter((e) => !watched.has(code(e))).reduce((a, e) => a + (e.runtime ?? 45), 0);

  return (
    <section className="space-y-5">
      <PayoffCurve seasons={seasons} watched={watched} today={today} />

      <div>
        <div className="mb-3 flex flex-wrap items-end justify-between gap-3">
          <div>
            <h2 className="font-display text-xl font-semibold tracking-tight">Episodes</h2>
            <p className="text-sm text-muted">
              {done} of {all.length} watched{remaining > 0 && done > 0 ? ` · ${runtimeLabel(remaining)} to go` : ""}
            </p>
          </div>
          <div className="h-2 w-40 overflow-hidden rounded-full bg-surface" aria-label={`${pct}% watched`}>
            <div className="h-full rounded-full bg-accent transition-all" style={{ width: `${pct}%` }} />
          </div>
        </div>

        <div className="rail -mx-1 mb-4 flex gap-2 overflow-x-auto px-1" role="tablist">
          {seasons.map((s) => (
            <button
              key={s.season_number}
              type="button"
              role="tab"
              aria-selected={s.season_number === active}
              onClick={() => setActive(s.season_number)}
              className={`shrink-0 rounded-full px-4 py-1.5 text-sm font-medium transition ${
                s.season_number === active ? "bg-accent text-on-accent" : "bg-surface text-muted hover:text-text"
              }`}
            >
              {s.season_number === 0 ? "Specials" : `Season ${s.season_number}`}
            </button>
          ))}
        </div>

        {airedHere.length > 0 && (
          <button
            type="button"
            onClick={() => actions.markSeason(show, season.season_number, airedHere.map((e) => e.episode_number), !seasonDone)}
            className="mb-3 text-sm font-medium text-accent hover:underline"
          >
            {seasonDone ? "Unmark season" : "Mark season watched"}
          </button>
        )}

        <ol className="space-y-2">
          {season.episodes.map((e) => {
            const isAired = aired(e, today);
            const isWatched = watched.has(code(e));
            const still = img(e.still_path, "w300");
            return (
              <li key={e.id} className={`flex gap-3 rounded-card bg-surface p-2.5 sm:gap-4 ${isAired ? "" : "opacity-60"}`}>
                <div className="relative aspect-video w-28 shrink-0 overflow-hidden rounded-[calc(var(--radius)*0.6)] bg-bg sm:w-40">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  {still && <img src={still} alt="" loading="lazy" className="h-full w-full object-cover" />}
                </div>
                <div className="min-w-0 flex-1 py-0.5">
                  <p className="text-xs text-muted">
                    E{e.episode_number} · {isAired ? formatDate(e.air_date) : `Airs ${formatDate(e.air_date)}`}
                    {e.runtime ? ` · ${runtimeLabel(e.runtime)}` : ""}
                    {e.vote_average ? ` · ★ ${e.vote_average.toFixed(1)}` : ""}
                  </p>
                  <p className="truncate font-medium">{e.name}</p>
                  <p className="mt-0.5 line-clamp-2 text-sm text-muted">{e.overview}</p>
                </div>
                <button
                  type="button"
                  disabled={!isAired}
                  onClick={() => actions.toggleEpisode(show, e.season_number, e.episode_number, e.runtime)}
                  aria-pressed={isWatched}
                  aria-label={isWatched ? `Mark episode ${e.episode_number} unwatched` : `Mark episode ${e.episode_number} watched`}
                  className={`grid size-9 shrink-0 place-items-center self-center rounded-full transition ${
                    isWatched ? "bg-accent text-on-accent" : "ring-1 ring-line hover:ring-accent disabled:hover:ring-line"
                  }`}
                >
                  <Check className="size-4" strokeWidth={3} />
                </button>
              </li>
            );
          })}
        </ol>
      </div>
    </section>
  );
}
