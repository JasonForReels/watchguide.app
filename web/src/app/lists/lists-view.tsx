"use client";

import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { useMemo, useState } from "react";
import { Pencil, Plus, Trash2, X } from "lucide-react";
import { PosterArt, PosterGridSkeleton } from "@/components/cards";
import { PageHeader } from "@/components/rail";
import { hrefOf } from "@/lib/media";
import { canCreateList, usePro } from "@/lib/purchases";
import { actions, useHydrated, useStore, type ListId } from "@/lib/store";
import type { SavedItem } from "@/lib/types";

type Tab = ListId | "watching" | `custom:${string}`;
type Sort = "added" | "title" | "year" | "rating";

const SORTS: { id: Sort; label: string }[] = [
  { id: "added", label: "Recently added" },
  { id: "title", label: "Title" },
  { id: "year", label: "Release date" },
  { id: "rating", label: "Rating" },
];

function sortItems(items: SavedItem[], sort: Sort, ratings: Record<string, number>) {
  const copy = [...items];
  switch (sort) {
    case "title": return copy.sort((a, b) => a.title.localeCompare(b.title));
    case "year": return copy.sort((a, b) => (b.date ?? "").localeCompare(a.date ?? ""));
    case "rating": return copy.sort((a, b) => (ratings[b.key] ?? 0) - (ratings[a.key] ?? 0) || (b.rating ?? 0) - (a.rating ?? 0));
    default: return copy.sort((a, b) => b.addedAt - a.addedAt);
  }
}

export function ListsView() {
  const params = useSearchParams();
  const router = useRouter();
  const hydrated = useHydrated();
  const lists = useStore((s) => s.lists);
  const custom = useStore((s) => s.custom);
  const pro = usePro();
  const episodes = useStore((s) => s.episodes);
  const ratings = useStore((s) => s.ratings);
  const tab = (params.get("tab") as Tab) || "want";
  const [sort, setSort] = useState<Sort>("added");
  const [type, setType] = useState<"all" | "movie" | "tv">("all");
  const [newName, setNewName] = useState("");
  const [editing, setEditing] = useState(false);

  const watching = useMemo(
    () => lists.want.filter((i) => i.type === "tv" && (episodes[String(i.id)]?.length ?? 0) > 0),
    [lists.want, episodes],
  );

  const customId = tab.startsWith("custom:") ? tab.slice(7) : null;
  const customList = custom.find((l) => l.id === customId);

  const tabs: { id: Tab; label: string; count: number }[] = [
    { id: "want", label: "Watchlist", count: lists.want.length },
    { id: "watching", label: "Watching", count: watching.length },
    { id: "watched", label: "Watched", count: lists.watched.length },
    { id: "liked", label: "Liked", count: lists.liked.length },
    ...custom.map((l) => ({ id: `custom:${l.id}` as Tab, label: l.name, count: l.items.length })),
  ];

  const source: SavedItem[] =
    tab === "watching" ? watching : customList ? customList.items : tab in lists ? lists[tab as ListId] : [];
  const items = sortItems(source.filter((i) => type === "all" || i.type === type), sort, ratings);

  const go = (t: Tab) => router.replace(`/lists?tab=${encodeURIComponent(t)}`, { scroll: false });

  const removeFrom = (item: SavedItem) => {
    if (customList) actions.toggleInCustom(customList.id, item);
    else if (tab === "watching") actions.remove("want", item.key);
    else actions.remove(tab as ListId, item.key);
  };

  return (
    <div className="pb-10">
      <PageHeader title="My Lists" />

      <div className="rail mb-5 flex gap-2.5 overflow-x-auto border-b border-line px-4 pb-4 sm:px-8" role="tablist">
        {tabs.map((t) => (
          <button
            key={t.id}
            type="button"
            role="tab"
            aria-selected={tab === t.id}
            onClick={() => go(t.id)}
            className={`press flex h-11 shrink-0 items-center gap-2 rounded-full px-4 text-[17px] transition ${tab === t.id ? "bg-tint font-semibold text-white" : "bg-surface text-text"}`}
          >
            {t.label}
            {hydrated && t.count > 0 && <span className={`rounded-md px-1.5 text-[12px] font-semibold tabular-nums ${tab === t.id ? "bg-white/25" : "bg-text/12 text-muted"}`}>{t.count}</span>}
          </button>
        ))}
        <form
          className="flex h-11 shrink-0 items-center gap-1 rounded-full bg-surface py-1 pr-1.5 pl-4 focus-within:ring-2 focus-within:ring-tint"
          onSubmit={(e) => {
            e.preventDefault();
            if (!newName.trim()) return;
            if (!canCreateList(pro.isPro, pro.status, custom.length)) { router.push("/pro"); return; }
            const id = actions.createList(newName);
            setNewName("");
            go(`custom:${id}`);
          }}
        >
          <input value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="New list" aria-label="New list name" className="w-24 bg-transparent text-sm outline-none" />
          <button type="submit" aria-label="Create list" className="grid size-8 place-items-center rounded-full bg-tint text-white"><Plus className="size-4" /></button>
        </form>
      </div>

      <div className="mb-6 flex flex-wrap items-center justify-between gap-3 px-4 sm:px-8">
        <div className="flex rounded-full bg-surface p-1">
          {(["all", "movie", "tv"] as const).map((t) => (
            <button key={t} type="button" onClick={() => setType(t)} className={`rounded-full px-4 py-1 text-[15px] transition ${type === t ? "bg-text/15 font-semibold" : "text-muted"}`}>
              {t === "all" ? "All" : t === "movie" ? "Films" : "Shows"}
            </button>
          ))}
        </div>
        <div className="flex items-center gap-3">
          {customList && (
            <>
              <button type="button" onClick={() => setEditing((e) => !e)} className="inline-flex items-center gap-1.5 text-sm text-muted hover:text-text"><Pencil className="size-3.5" /> Rename</button>
              <button
                type="button"
                onClick={() => {
                  if (confirm(`Delete "${customList.name}"? This can't be undone.`)) {
                    actions.deleteList(customList.id);
                    go("want");
                  }
                }}
                className="inline-flex items-center gap-1.5 text-sm text-muted hover:text-red-400"
              >
                <Trash2 className="size-3.5" /> Delete
              </button>
            </>
          )}
          <label className="flex items-center gap-2 text-sm text-muted">
            Sort
            <select value={sort} onChange={(e) => setSort(e.target.value as Sort)} className="rounded-lg bg-surface px-2.5 py-1.5 text-sm text-text ring-1 ring-line outline-none">
              {SORTS.map((s) => <option key={s.id} value={s.id}>{s.label}</option>)}
            </select>
          </label>
        </div>
      </div>

      {customList && editing && (
        <form
          className="mb-6 flex max-w-md gap-2 px-4 sm:px-8"
          onSubmit={(e) => {
            e.preventDefault();
            const name = new FormData(e.currentTarget).get("name") as string;
            if (name.trim()) actions.renameList(customList.id, name.trim());
            setEditing(false);
          }}
        >
          <input name="name" defaultValue={customList.name} autoFocus aria-label="List name" className="flex-1 rounded-lg bg-surface px-3 py-2 text-sm ring-1 ring-line outline-none focus:ring-accent" />
          <button type="submit" className="rounded-lg bg-accent px-4 text-sm font-semibold text-on-accent">Save</button>
        </form>
      )}

      <div className="px-4 sm:px-8">
        {!hydrated ? (
          <PosterGridSkeleton count={6} />
        ) : !items.length ? (
          <Empty tab={tab} />
        ) : (
          <div className="grid grid-cols-[repeat(auto-fill,minmax(8.5rem,1fr))] gap-x-4 gap-y-6 sm:grid-cols-[repeat(auto-fill,minmax(10rem,1fr))]">
            {items.map((item) => {
              const eps = episodes[String(item.id)]?.length ?? 0;
              const stars = ratings[item.key];
              return (
                <div key={item.key} className="group relative">
                  <Link href={hrefOf(item.type, item.id)} className="block">
                    <div className="frame relative aspect-[2/3] overflow-hidden rounded-card bg-surface transition-transform duration-300 group-hover:-translate-y-1">
                      <PosterArt path={item.poster} alt={item.title} />
                      {item.type === "tv" && eps > 0 && (
                        <span className="absolute bottom-2 left-2 rounded-full bg-black/75 px-2 py-0.5 text-[11px] font-semibold text-white backdrop-blur">{eps} ep{eps === 1 ? "" : "s"}</span>
                      )}
                    </div>
                    <p className="mt-2 truncate text-sm font-medium">{item.title}</p>
                    <p className="text-xs text-muted">
                      {item.year ?? "TBA"} · {item.type === "tv" ? "Show" : "Film"}
                      {stars ? <span className="text-accent"> · {"★".repeat(stars)}</span> : null}
                    </p>
                  </Link>
                  <button
                    type="button"
                    onClick={() => removeFrom(item)}
                    aria-label={`Remove ${item.title}`}
                    className="absolute top-2 right-2 grid size-7 place-items-center rounded-full bg-black/70 text-white opacity-0 backdrop-blur transition group-hover:opacity-100 focus:opacity-100 [@media(hover:none)]:opacity-100"
                  >
                    <X className="size-3.5" />
                  </button>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

function Empty({ tab }: { tab: Tab }) {
  const copy: Record<string, [string, string]> = {
    want: ["Your watchlist is empty", "Save anything from Browse, Search or Tonight and it lands here."],
    watching: ["Nothing in progress", "Tick off an episode on any show page to start tracking it."],
    watched: ["Nothing watched yet", "Mark films as watched, or finish a show, to build your history."],
    liked: ["No likes yet", "Tap the heart on anything you love. It shapes your picks."],
  };
  const [title, body] = copy[tab] ?? ["This list is empty", "Use the folder button on any title to add it here."];
  return (
    <div className="mx-auto max-w-sm py-16 text-center">
      <div className="marquee-bulbs mx-auto mb-5 w-16" aria-hidden="true" />
      <p className="font-display text-xl font-semibold">{title}</p>
      <p className="mt-1.5 text-sm text-muted">{body}</p>
      <Link href="/tonight" className="mt-5 inline-block rounded-full bg-accent px-5 py-2.5 text-sm font-semibold text-on-accent">Find something tonight</Link>
    </div>
  );
}
