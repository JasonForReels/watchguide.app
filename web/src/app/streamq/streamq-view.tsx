"use client";

import { useMemo, useState } from "react";
import { Check } from "lucide-react";
import { PosterCard } from "@/components/cards";
import { PageHeader, Rail, RailSkeleton } from "@/components/rail";
import { useApi } from "@/lib/api";
import { REGIONS, SERVICES } from "@/lib/catalog";
import { img, keyOf } from "@/lib/media";
import { actions, addDays, useHydrated, useStore, useToday } from "@/lib/store";
import type { MediaItem, MediaType, Paged } from "@/lib/types";

function useProviderRow(type: MediaType, providers: number[], region: string, extra: Record<string, string | number> = {}) {
  return useApi<Paged<MediaItem>>(providers.length ? `discover/${type}` : null, {
    with_watch_providers: providers.join("|"),
    watch_region: region,
    with_watch_monetization_types: "flatrate|free|ads",
    ...extra,
  });
}

function ProviderRail({ title, subtitle, type, providers, region, extra }: { title: string; subtitle?: string; type: MediaType; providers: number[]; region: string; extra?: Record<string, string | number> }) {
  const { data, loading } = useProviderRow(type, providers, region, extra);
  const watched = useStore((s) => s.lists.watched);
  const items = useMemo(() => {
    const seen = new Set(watched.map((w) => w.key));
    return (data?.results ?? []).filter((i) => i.poster_path && !seen.has(keyOf(type, i.id)));
  }, [data, watched, type]);
  if (loading) return <RailSkeleton />;
  if (!items.length) return null;
  return (
    <Rail title={title} subtitle={subtitle}>
      {items.map((i) => <PosterCard key={i.id} item={i} type={type} />)}
    </Rail>
  );
}

export function StreamQView() {
  const hydrated = useHydrated();
  const services = useStore((s) => s.settings.services);
  const region = useStore((s) => s.settings.region);
  const [editing, setEditing] = useState(false);
  const today = useToday();
  const monthAgo = today ? addDays(today, -45) : null;
  const mine = SERVICES.filter((s) => services.includes(s.id));
  const picking = editing || (hydrated && !services.length);

  return (
    <div className="space-y-9 pb-10">
      <PageHeader root title="StreamQ" subtitle="What's on the services you already pay for, and nothing you'd have to rent.">
        {hydrated && services.length > 0 && (
          <button type="button" onClick={() => setEditing((e) => !e)} className="rounded-full bg-surface px-4 py-2 text-sm font-medium ring-1 ring-line hover:ring-accent">
            {editing ? "Done" : "Edit services"}
          </button>
        )}
      </PageHeader>

      {picking && (
        <section className="px-4 sm:px-8">
          <div className="rounded-card border border-line bg-surface p-5 sm:p-6">
            <div className="mb-5 flex flex-wrap items-end justify-between gap-3">
              <div>
                <h2 className="font-display text-xl font-semibold">Pick your services</h2>
                <p className="text-sm text-muted">We&apos;ll only show what you can watch without paying extra.</p>
              </div>
              <label className="flex items-center gap-2 text-sm text-muted">
                Region
                <select value={region} onChange={(e) => actions.updateSettings({ region: e.target.value })} className="rounded-lg bg-bg px-2.5 py-1.5 text-sm text-text ring-1 ring-line outline-none">
                  {REGIONS.map((r) => <option key={r.code} value={r.code}>{r.name}</option>)}
                </select>
              </label>
            </div>
            <div className="grid grid-cols-3 gap-3 sm:grid-cols-5 lg:grid-cols-8">
              {SERVICES.map((s) => {
                const on = services.includes(s.id);
                return (
                  <button
                    key={s.id}
                    type="button"
                    aria-pressed={on}
                    onClick={() => actions.toggleService(s.id)}
                    className={`relative flex flex-col items-center gap-2 rounded-xl p-3 text-xs font-medium transition ${on ? "bg-accent/15 ring-2 ring-accent" : "ring-1 ring-line hover:bg-raised"}`}
                  >
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={img(s.logo, "w92")!} alt="" className="size-12 rounded-xl" />
                    <span className="line-clamp-1">{s.name}</span>
                    {on && <span className="absolute top-1.5 right-1.5 grid size-5 place-items-center rounded-full bg-accent text-on-accent"><Check className="size-3" strokeWidth={3} /></span>}
                  </button>
                );
              })}
            </div>
          </div>
        </section>
      )}

      {hydrated && today && monthAgo && services.length > 0 && (
        <>
          <div className="rail flex gap-2 overflow-x-auto px-4 sm:px-8">
            {mine.map((s) => (
              <span key={s.id} className="flex shrink-0 items-center gap-2 rounded-full bg-surface py-1 pr-3.5 pl-1 text-sm ring-1 ring-line">
                {/* eslint-disable-next-line @next/next/no-img-element */}
                <img src={img(s.logo, "w92")!} alt="" className="size-7 rounded-full" />
                {s.name}
              </span>
            ))}
          </div>
          <ProviderRail title="New on your services" subtitle="Films added in the last few weeks" type="movie" providers={services} region={region} extra={{ sort_by: "primary_release_date.desc", "primary_release_date.lte": today, "primary_release_date.gte": monthAgo, "vote_count.gte": 5 }} />
          <ProviderRail title="New episodes" subtitle="Shows that aired recently" type="tv" providers={services} region={region} extra={{ sort_by: "popularity.desc", "air_date.gte": monthAgo, "air_date.lte": today }} />
          <ProviderRail title="Popular films" type="movie" providers={services} region={region} extra={{ sort_by: "popularity.desc" }} />
          <ProviderRail title="Popular shows" type="tv" providers={services} region={region} extra={{ sort_by: "popularity.desc" }} />
          <ProviderRail title="Hidden gems" subtitle="Highly rated, under the radar" type="movie" providers={services} region={region} extra={{ sort_by: "vote_average.desc", "vote_count.gte": 300, "vote_count.lte": 3000 }} />
          {mine.slice(0, 6).map((s) => (
            <ProviderRail key={s.id} title={`Top on ${s.name}`} type="tv" providers={[s.id]} region={region} extra={{ sort_by: "popularity.desc" }} />
          ))}
        </>
      )}
    </div>
  );
}
