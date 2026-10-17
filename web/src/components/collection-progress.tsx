"use client";

import { actions, useStore, useToday } from "@/lib/store";
import type { SavedItem } from "@/lib/types";

export function CollectionProgress({ items }: { items: SavedItem[] }) {
  const watched = useStore((s) => s.lists.watched);
  const today = useToday();
  const released = today ? items.filter((i) => i.date && i.date <= today) : [];
  const seen = released.filter((i) => watched.some((w) => w.key === i.key)).length;
  const pct = released.length ? Math.round((seen / released.length) * 100) : 0;

  return (
    <div className="mt-6 flex flex-wrap items-center gap-4 rounded-card border border-line bg-surface p-4">
      <div className="flex-1">
        <p className="text-sm font-medium">
          You&apos;ve seen {seen} of {released.length}
        </p>
        <div className="mt-2 h-2 overflow-hidden rounded-full bg-bg">
          <div className="h-full rounded-full bg-accent transition-all" style={{ width: `${pct}%` }} />
        </div>
      </div>
      {seen < released.length && (
        <button type="button" onClick={() => released.forEach((i) => actions.add("want", i))} className="rounded-full bg-accent px-4 py-2 text-sm font-semibold text-on-accent">
          Add the rest to Watchlist
        </button>
      )}
    </div>
  );
}
