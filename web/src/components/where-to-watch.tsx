"use client";

import { REGIONS } from "@/lib/catalog";
import { img } from "@/lib/media";
import { actions, useStore } from "@/lib/store";
import type { Provider, RegionProviders } from "@/lib/types";

const KINDS: { key: keyof RegionProviders; label: string }[] = [
  { key: "flatrate", label: "Stream" },
  { key: "free", label: "Free" },
  { key: "ads", label: "With ads" },
  { key: "rent", label: "Rent" },
  { key: "buy", label: "Buy" },
];

export function WhereToWatch({ providers }: { providers: Record<string, RegionProviders> }) {
  const region = useStore((s) => s.settings.region);
  const mine = useStore((s) => s.settings.services);
  const data = providers[region];
  const available = REGIONS.filter((r) => providers[r.code]);

  return (
    <section>
      <div className="mb-3 flex flex-wrap items-center justify-between gap-3">
        <h2 className="font-display text-xl font-semibold tracking-tight">Where to watch</h2>
        <label className="flex items-center gap-2 text-sm text-muted">
          Region
          <select
            value={region}
            onChange={(e) => actions.updateSettings({ region: e.target.value })}
            className="rounded-lg bg-surface px-2.5 py-1.5 text-sm text-text ring-1 ring-line outline-none focus:ring-accent"
          >
            {REGIONS.map((r) => (
              <option key={r.code} value={r.code}>
                {r.name}
                {providers[r.code] ? "" : " (none)"}
              </option>
            ))}
          </select>
        </label>
      </div>
      {!data ? (
        <p className="rounded-card bg-surface p-4 text-sm text-muted">
          Not available to stream in {REGIONS.find((r) => r.code === region)?.name ?? region} yet.
          {available.length > 0 && ` It is in ${available.slice(0, 4).map((r) => r.name).join(", ")}.`}
        </p>
      ) : (
        <div className="space-y-4">
          {KINDS.map(({ key, label }) => {
            const list = data[key] as Provider[] | undefined;
            if (!list?.length) return null;
            return (
              <div key={key}>
                <p className="mb-2 text-xs font-semibold uppercase tracking-wider text-faint">{label}</p>
                <div className="flex flex-wrap gap-2.5">
                  {list.map((p) => {
                    const yours = mine.includes(p.provider_id);
                    return (
                      <a
                        key={p.provider_id}
                        href={data.link}
                        target="_blank"
                        rel="noreferrer"
                        title={p.provider_name}
                        className={`flex items-center gap-2 rounded-xl bg-surface py-1.5 pr-3 pl-1.5 text-sm transition hover:bg-raised ${yours ? "ring-2 ring-accent" : "ring-1 ring-line"}`}
                      >
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img src={img(p.logo_path, "w92") ?? ""} alt="" className="size-8 rounded-lg" />
                        <span className="max-w-36 truncate">{p.provider_name}</span>
                        {yours && <span className="text-[10px] font-semibold uppercase text-accent">Yours</span>}
                      </a>
                    );
                  })}
                </div>
              </div>
            );
          })}
          <p className="text-xs text-faint">Availability from JustWatch via TMDB.</p>
        </div>
      )}
    </section>
  );
}
