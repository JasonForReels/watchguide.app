"use client";

import { useEffect, useRef, useState } from "react";
import { Bookmark, Check, FolderPlus, Heart, ListPlus, Plus, Star } from "lucide-react";
import { useRouter } from "next/navigation";
import { toSaved } from "@/lib/media";
import { canCreateList, usePro } from "@/lib/purchases";
import { actions, useStore } from "@/lib/store";
import type { MediaItem, MediaType, TitleDetails } from "@/lib/types";

type Source = MediaItem | TitleDetails;

const glass = "bg-white/15 text-white backdrop-blur-md hover:bg-white/25";

export function SaveButton({ item, type, variant = "solid" }: { item: Source; type: MediaType; variant?: "solid" | "glass" }) {
  const key = `${type}-${item.id}`;
  const saved = useStore((s) => s.lists.want.some((i) => i.key === key));
  return (
    <button
      type="button"
      onClick={() => actions.toggle("want", toSaved(item, type))}
      aria-pressed={saved}
      className={`inline-flex items-center gap-2 rounded-full px-5 py-2.5 text-sm font-semibold transition ${
        variant === "glass" ? glass : saved ? "bg-surface text-text ring-1 ring-accent" : "bg-surface text-text hover:bg-raised"
      }`}
    >
      {saved ? <Check className="size-4 text-accent" strokeWidth={3} /> : <Plus className="size-4" strokeWidth={2.5} />}
      {saved ? "On Watchlist" : "Watchlist"}
    </button>
  );
}

/** Watchlist / Watched / Liked / Add to list, as on the iOS detail page. */
export function ListActions({ item, type }: { item: Source; type: MediaType }) {
  const key = `${type}-${item.id}`;
  const lists = useStore((s) => ({
    want: s.lists.want.some((i) => i.key === key),
    watched: s.lists.watched.some((i) => i.key === key),
    liked: s.lists.liked.some((i) => i.key === key),
  }));
  const saved = toSaved(item, type);

  const btn = (on: boolean) =>
    `inline-flex items-center gap-2 rounded-full px-4 py-2.5 text-sm font-semibold transition ${
      on ? "bg-accent text-on-accent" : "bg-white/10 text-text ring-1 ring-line hover:bg-white/15"
    }`;

  return (
    <div className="flex flex-wrap items-center gap-2.5">
      <button type="button" className={btn(lists.want)} aria-pressed={lists.want} onClick={() => actions.toggle("want", saved)}>
        <Bookmark className={`size-4 ${lists.want ? "fill-current" : ""}`} /> {lists.want ? "On Watchlist" : "Watchlist"}
      </button>
      {type === "movie" && (
        <button type="button" className={btn(lists.watched)} aria-pressed={lists.watched} onClick={() => actions.toggle("watched", saved)}>
          <Check className="size-4" strokeWidth={3} /> {lists.watched ? "Watched" : "Mark watched"}
        </button>
      )}
      {type === "tv" && (
        <button type="button" className={btn(lists.watched)} aria-pressed={lists.watched} onClick={() => actions.toggle("watched", saved)}>
          <Check className="size-4" strokeWidth={3} /> {lists.watched ? "Finished" : "Finished it"}
        </button>
      )}
      <button
        type="button"
        className={`grid size-10 place-items-center rounded-full transition ${lists.liked ? "bg-accent text-on-accent" : "bg-white/10 ring-1 ring-line hover:bg-white/15"}`}
        aria-pressed={lists.liked}
        aria-label={lists.liked ? "Unlike" : "Like"}
        onClick={() => actions.toggle("liked", saved)}
      >
        <Heart className={`size-4 ${lists.liked ? "fill-current" : ""}`} />
      </button>
      <AddToList item={item} type={type} />
    </div>
  );
}

export function AddToList({ item, type, labeled = false }: { item: Source; type: MediaType; labeled?: boolean }) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const custom = useStore((s) => s.custom);
  const pro = usePro();
  const router = useRouter();
  const key = `${type}-${item.id}`;
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const close = (e: MouseEvent) => {
      if (!ref.current?.contains(e.target as Node)) setOpen(false);
    };
    const esc = (e: KeyboardEvent) => e.key === "Escape" && setOpen(false);
    document.addEventListener("mousedown", close);
    document.addEventListener("keydown", esc);
    return () => {
      document.removeEventListener("mousedown", close);
      document.removeEventListener("keydown", esc);
    };
  }, [open]);

  return (
    <div className="relative" ref={ref}>
      {labeled ? (
        <button type="button" aria-expanded={open} onClick={() => setOpen((o) => !o)} className="press flex w-16 flex-col items-center gap-1.5 text-[13px] font-medium text-text/80">
          <span className="glass-clear grid size-12 place-items-center rounded-full"><ListPlus className="size-[22px]" /></span>
          Lists
        </button>
      ) : (
        <button
          type="button"
          aria-label="Add to a list"
          aria-expanded={open}
          onClick={() => setOpen((o) => !o)}
          className="grid size-10 place-items-center rounded-full bg-white/10 ring-1 ring-line transition hover:bg-white/15"
        >
          <FolderPlus className="size-4" />
        </button>
      )}
      {open && (
        <div className={`rise absolute top-16 z-30 w-64 rounded-2xl border border-line bg-surface p-2 text-left shadow-2xl ${labeled ? "left-1/2 -translate-x-1/2" : "left-0"}`}>
          <p className="px-2 pt-1 pb-2 text-xs font-semibold uppercase tracking-wider text-faint">Add to list</p>
          {custom.length === 0 && <p className="px-2 pb-2 text-sm text-muted">No lists yet. Make one below.</p>}
          <ul className="max-h-56 overflow-y-auto">
            {custom.map((l) => {
              const has = l.items.some((i) => i.key === key);
              return (
                <li key={l.id}>
                  <button
                    type="button"
                    onClick={() => actions.toggleInCustom(l.id, toSaved(item, type))}
                    className="flex w-full items-center justify-between rounded-lg px-2 py-2 text-left text-sm hover:bg-white/5"
                  >
                    <span className="truncate">{l.name}</span>
                    {has && <Check className="size-4 text-accent" strokeWidth={3} />}
                  </button>
                </li>
              );
            })}
          </ul>
          <form
            className="mt-1 flex gap-1.5 border-t border-line pt-2"
            onSubmit={(e) => {
              e.preventDefault();
              if (!name.trim()) return;
              if (!canCreateList(pro.isPro, pro.status, custom.length)) { router.push("/pro"); return; }
              const id = actions.createList(name);
              actions.toggleInCustom(id, toSaved(item, type));
              setName("");
            }}
          >
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="New list name"
              aria-label="New list name"
              className="min-w-0 flex-1 rounded-lg bg-bg px-2.5 py-1.5 text-sm outline-none ring-1 ring-line focus:ring-accent"
            />
            <button type="submit" className="rounded-lg bg-accent px-2.5 text-sm font-semibold text-on-accent">
              Add
            </button>
          </form>
        </div>
      )}
    </div>
  );
}

export function StarRating({ k }: { k: string }) {
  const value = useStore((s) => s.ratings[k] ?? 0);
  const [hover, setHover] = useState(0);
  const shown = hover || value;
  return (
    <div className="flex items-center gap-1" onMouseLeave={() => setHover(0)} role="radiogroup" aria-label="Your rating">
      {[1, 2, 3, 4, 5].map((n) => (
        <button
          key={n}
          type="button"
          role="radio"
          aria-checked={value === n}
          aria-label={`${n} star${n > 1 ? "s" : ""}`}
          onMouseEnter={() => setHover(n)}
          onClick={() => actions.rate(k, n)}
          className="p-0.5"
        >
          <Star className={`size-5 transition ${n <= shown ? "fill-accent text-accent" : "text-faint"}`} />
        </button>
      ))}
    </div>
  );
}
