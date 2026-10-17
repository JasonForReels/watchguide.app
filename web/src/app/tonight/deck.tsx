"use client";

/*
 * Tonight answers one question: what should we watch right now? It shows one
 * title at a time. Swipe right to save it, left to skip, or up once you've
 * watched it. Every swipe can be undone. Ported from TonightReelView.swift.
 */

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Bookmark, Info, RotateCcw, Ticket, Undo2, X } from "lucide-react";
import { api } from "@/lib/api";
import { genreName } from "@/lib/catalog";
import { fromSaved, hrefOf, img, keyOf, titleOf, toSaved, typeOf, yearOf } from "@/lib/media";
import { actions, getState, startOfDay, useHydrated, useStore, useToday } from "@/lib/store";
import type { MediaItem, Paged } from "@/lib/types";

type Kind = "everything" | "movie" | "tv";
type Action = "skip" | "save" | "watched";

interface Swipe {
  item: MediaItem;
  action: Action;
  wasSaved: boolean;
}

const KINDS: { id: Kind; label: string }[] = [
  { id: "everything", label: "Everything" },
  { id: "movie", label: "Movies" },
  { id: "tv", label: "Shows" },
];

/** The genres you save and finish most, used to bias the fresh picks. */
function topGenres(): number[] {
  const s = getState();
  const counts = new Map<number, number>();
  for (const i of [...s.lists.liked, ...s.lists.watched, ...s.lists.want]) for (const g of i.genres) counts.set(g, (counts.get(g) ?? 0) + 1);
  return [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 3).map(([g]) => g);
}

export function TonightDeck() {
  const hydrated = useHydrated();
  const [kind, setKind] = useState<Kind>("everything");
  const [deck, setDeck] = useState<MediaItem[]>([]);
  const [history, setHistory] = useState<Swipe[]>([]);
  const [loading, setLoading] = useState(false);
  const [failed, setFailed] = useState(false);
  const router = useRouter();
  const close = () => (window.history.length > 1 ? router.back() : router.push("/"));
  const page = useRef(1);
  const generation = useRef(0);
  const today = useToday();
  const log = useStore((s) => s.log);
  const watchedToday = today ? log.filter((e) => e.at >= startOfDay(today)).length : 0;

  const matches = useCallback((item: MediaItem) => kind === "everything" || typeOf(item) === kind, [kind]);

  const excluded = useCallback(() => {
    const s = getState();
    return new Set([...s.skipped, ...s.lists.watched.map((i) => i.key)]);
  }, []);

  const loadMore = useCallback(async () => {
    const gen = generation.current;
    setLoading(true);
    setFailed(false);
    try {
      const p = page.current++;
      if (p === 1) {
        // The deck opens instantly with your own watchlist, then fresh picks fill in behind.
        const s = getState();
        const skip = new Set(s.skipped);
        setDeck(
          s.lists.want
            .filter((i) => !skip.has(i.key) && i.backdrop && (kind === "everything" || i.type === kind))
            .slice(0, 8)
            .map(fromSaved),
        );
      }
      const genres = topGenres();
      const types: ("movie" | "tv")[] = kind === "everything" ? ["movie", "tv"] : [kind];
      const requests: Promise<MediaItem[]>[] = [
        api<Paged<MediaItem>>(`trending/${kind === "everything" ? "all" : kind}/week`, { page: p }).then((r) => r.results),
        ...types.map((t) =>
          api<Paged<MediaItem>>(`discover/${t}`, {
            page: p,
            sort_by: "popularity.desc",
            "vote_average.gte": 6.8,
            "vote_count.gte": 300,
            with_genres: genres.length ? genres.join("|") : undefined,
          }).then((r) => r.results.map((i) => ({ ...i, media_type: t }))),
        ),
      ];
      const batches = await Promise.all(requests);
      if (gen !== generation.current) return;
      // Interleave the sources so the deck alternates trending and taste picks.
      const mixed: MediaItem[] = [];
      const longest = Math.max(...batches.map((b) => b.length));
      for (let i = 0; i < longest; i++) for (const b of batches) if (b[i]) mixed.push(b[i]);
      const skip = excluded();
      setDeck((d) => {
        const have = new Set(d.map((i) => keyOf(typeOf(i), i.id)));
        const fresh = mixed.filter((i) => {
          if (i.media_type === "person" || !i.backdrop_path || !i.poster_path) return false;
          const k = keyOf(typeOf(i), i.id);
          if (have.has(k) || skip.has(k)) return false;
          have.add(k);
          return matches(i);
        });
        return [...d, ...fresh];
      });
    } catch {
      if (gen === generation.current) setFailed(true);
    } finally {
      if (gen === generation.current) setLoading(false);
    }
  }, [kind, excluded, matches]);

  /** Clears the deck; the effect below then refills it from page 1. Called from event handlers. */
  const restart = useCallback(() => {
    generation.current++;
    page.current = 1;
    setHistory([]);
    setDeck([]);
    setLoading(false);
    setFailed(false);
  }, []);

  const changeKind = (k: Kind) => {
    if (k === kind) return;
    setKind(k);
    restart();
  };

  // Fetch whenever the deck runs low, including the first load once local data is readable.
  useEffect(() => {
    if (hydrated && deck.length < 4 && !loading && !failed && page.current < 12) void loadMore();
  }, [deck.length, hydrated, loading, failed, loadMore]);

  const swipe = useCallback(
    (action: Action) => {
      const item = deck[0];
      if (!item) return;
      const type = typeOf(item);
      const saved = toSaved(item, type);
      const wasSaved = getState().lists.want.some((i) => i.key === saved.key);
      if (action === "skip") actions.skip(saved.key);
      if (action === "save") actions.add("want", saved);
      if (action === "watched") actions.add("watched", saved);
      setHistory((h) => [...h.slice(-30), { item, action, wasSaved }]);
      setDeck((d) => d.slice(1));
    },
    [deck],
  );

  const undo = useCallback(() => {
    const last = history.at(-1);
    if (!last) return;
    const k = keyOf(typeOf(last.item), last.item.id);
    if (last.action === "skip") actions.unskip(k);
    if (last.action === "save" && !last.wasSaved) actions.remove("want", k);
    if (last.action === "watched") {
      actions.remove("watched", k);
      if (last.wasSaved) actions.add("want", toSaved(last.item, typeOf(last.item)));
    }
    setHistory((h) => h.slice(0, -1));
    setDeck((d) => [last.item, ...d]);
  }, [history]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof Element && e.target.closest("input,textarea,select")) return;
      if (e.key === "ArrowLeft") swipe("skip");
      else if (e.key === "ArrowRight") swipe("save");
      else if (e.key === "ArrowUp") { e.preventDefault(); swipe("watched"); }
      else if ((e.metaKey || e.ctrlKey) && e.key === "z") { e.preventDefault(); undo(); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [swipe, undo]);

  const top = deck[0];
  const topSaved = useStore((st) => (top ? st.lists.want.some((i) => i.key === keyOf(typeOf(top), top.id)) : false));

  return (
    <div className="relative min-h-dvh overflow-hidden pb-10">
      {/* Background tint from the card on top, as the iOS reel does. */}
      <div className="pointer-events-none fixed inset-0 z-0 bg-bg" aria-hidden>
        {top?.poster_path && (
          // eslint-disable-next-line @next/next/no-img-element
          <img key={top.id} src={img(top.poster_path, "w185") ?? ""} alt="" className="rise h-full w-full scale-150 object-cover opacity-60 blur-[90px] saturate-150" />
        )}
        <div className="absolute inset-0 bg-black/50" />
      </div>

      <div className="relative z-10 mx-auto max-w-xl px-4 pt-[max(env(safe-area-inset-top),16px)] text-white">
        <div className="flex items-center justify-between">
          <button type="button" onClick={close} className="glass-clear press h-11 rounded-full px-5 text-[17px] font-medium">Close</button>
          <div className="glass-clear flex items-center rounded-full p-1">
            <button type="button" aria-label="Undo" title="Undo (⌘Z)" onClick={undo} disabled={!history.length} className="press grid size-10 place-items-center rounded-full disabled:opacity-35">
              <Undo2 className="size-5" />
            </button>
            {top ? (
              <Link href={hrefOf(typeOf(top), top.id)} aria-label="Details" className="press grid size-10 place-items-center rounded-full">
                <Info className="size-5" />
              </Link>
            ) : <span className="size-10" />}
          </div>
        </div>

        <h1 className="large-title mt-3 mb-3">Tonight</h1>
        <div className="glass-clear mb-5 grid grid-cols-3 rounded-full p-1" role="tablist">
          {KINDS.map((k) => (
            <button
              key={k.id}
              type="button"
              role="tab"
              aria-selected={kind === k.id}
              onClick={() => changeKind(k.id)}
              className={`rounded-full py-1.5 text-[15px] font-medium transition ${kind === k.id ? "bg-white/25" : "text-white/85"}`}
            >
              {k.label}
            </button>
          ))}
        </div>

        <div className="relative mx-auto aspect-[2/3] max-h-[62dvh] w-full max-w-[min(100%,calc(62dvh*2/3))]">
          {deck.slice(0, 3).reverse().map((item, i, arr) => (
            <Card key={`${typeOf(item)}-${item.id}`} item={item} depth={arr.length - 1 - i} onSwipe={swipe} />
          ))}
          {!deck.length && (
            <div className="grid h-full place-items-center rounded-[28px] bg-white/10 p-8 text-center backdrop-blur">
              {loading || !hydrated ? (
                <div className="skeleton absolute inset-0 rounded-[28px]" />
              ) : failed ? (
                <div>
                  <p className="font-semibold">Couldn&apos;t load picks</p>
                  <p className="mt-1 text-sm text-white/70">Check your connection and try again.</p>
                  <button type="button" onClick={() => setFailed(false)} className="mt-4 rounded-full bg-accent px-4 py-2 text-sm font-semibold text-on-accent">Try again</button>
                </div>
              ) : (
                <div>
                  <p className="font-display text-xl font-semibold">That&apos;s the reel.</p>
                  <p className="mt-1 text-sm text-white/70">You&apos;ve been through everything for now.</p>
                  <button type="button" onClick={() => { actions.resetSkipped(); restart(); }} className="mt-4 inline-flex items-center gap-2 rounded-full bg-accent px-4 py-2 text-sm font-semibold text-on-accent">
                    <RotateCcw className="size-4" /> Start over
                  </button>
                </div>
              )}
            </div>
          )}
        </div>

        <div className="mt-6 flex items-center justify-center gap-6">
          <CircleButton label="Skip" onClick={() => swipe("skip")} disabled={!deck.length}><X className="size-7" strokeWidth={2.4} /></CircleButton>
          <button
            type="button"
            onClick={() => swipe("watched")}
            disabled={!deck.length}
            className="press inline-flex h-[72px] items-center gap-2.5 rounded-full bg-accent px-9 text-[19px] font-semibold text-white shadow-lg shadow-black/30 disabled:opacity-40"
          >
            <Ticket className="size-6" /> Watched
          </button>
          <CircleButton label={topSaved ? "On your watchlist" : "Save to watchlist"} onClick={() => swipe("save")} disabled={!deck.length}>
            <Bookmark className={`size-6 ${topSaved ? "fill-current" : ""}`} strokeWidth={2.2} />
          </CircleButton>
        </div>
        <p className="mt-5 hidden text-center text-xs text-white/50 md:block">
          Keyboard: ← skip · → save · ↑ watched · ⌘Z undo
          {hydrated && watchedToday > 0 && ` · ${watchedToday} watched today`}
        </p>
      </div>
    </div>
  );
}

function CircleButton({ children, label, onClick, disabled }: { children: React.ReactNode; label: string; onClick: () => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      aria-label={label}
      title={label}
      onClick={onClick}
      disabled={disabled}
      className="glass-clear press grid size-[72px] place-items-center rounded-full disabled:opacity-40"
    >
      {children}
    </button>
  );
}

function Card({ item, depth, onSwipe }: { item: MediaItem; depth: number; onSwipe: (a: Action) => void }) {
  const [drag, setDrag] = useState({ x: 0, y: 0, active: false });
  const start = useRef<{ x: number; y: number } | null>(null);
  const type = typeOf(item);
  const genres = useMemo(() => (item.genre_ids ?? []).slice(0, 3).map(genreName).filter(Boolean), [item]);
  const top = depth === 0;
  const onWatchlist = useStore((st) => st.lists.want.some((i) => i.key === keyOf(type, item.id)));

  const intent: Action | null = drag.x > 90 ? "save" : drag.x < -90 ? "skip" : drag.y < -110 ? "watched" : null;

  const end = () => {
    start.current = null;
    if (intent) onSwipe(intent);
    setDrag({ x: 0, y: 0, active: false });
  };

  return (
    <div
      className="absolute inset-0 touch-none select-none"
      style={{
        transform: top
          ? `translate(${drag.x}px, ${Math.min(drag.y, 40)}px) rotate(${drag.x / 18}deg)`
          : `translateY(${depth * 14}px) scale(${1 - depth * 0.05})`,
        transition: drag.active ? "none" : "transform 0.35s cubic-bezier(0.2,0.8,0.2,1)",
        zIndex: 10 - depth,
        opacity: depth > 1 ? 0.6 : 1,
      }}
      onPointerDown={(e) => {
        if (!top) return;
        start.current = { x: e.clientX, y: e.clientY };
        (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
        setDrag((d) => ({ ...d, active: true }));
      }}
      onPointerMove={(e) => {
        if (!start.current) return;
        setDrag({ x: e.clientX - start.current.x, y: e.clientY - start.current.y, active: true });
      }}
      onPointerUp={end}
      onPointerCancel={end}
    >
      <div className="relative h-full overflow-hidden rounded-[28px] bg-surface shadow-2xl shadow-black/50">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={img(item.poster_path, "w500") ?? ""} alt="" draggable={false} className="absolute inset-0 h-full w-full object-cover" />

        {top && intent && (
          <div
            className={`absolute top-8 rounded-xl border-4 px-4 py-1.5 font-display text-2xl font-black tracking-wider uppercase ${
              intent === "save" ? "left-6 -rotate-12 border-accent text-accent" : intent === "skip" ? "right-6 rotate-12 border-white text-white" : "left-1/2 -translate-x-1/2 border-white text-white"
            }`}
          >
            {intent === "save" ? "Save" : intent === "skip" ? "Nope" : "Seen it"}
          </div>
        )}
        <div className="absolute inset-x-0 bottom-0 bg-black/35 px-5 pt-4 pb-5 text-white backdrop-blur-2xl">
          <p className="flex items-center gap-1.5 text-[15px] font-semibold text-accent">
            {onWatchlist ? <><Bookmark className="size-4 fill-current" /> On Your Watchlist</> : genres[0] ?? (type === "tv" ? "Series" : "Movie")}
          </p>
          <h2 className="mt-1 text-[24px] leading-tight font-bold">{titleOf(item)}</h2>
          <p className="mt-1 text-[17px] text-white/65">
            {[type === "tv" ? "Series" : "Movie", yearOf(item), item.vote_average ? `★ ${item.vote_average.toFixed(1)}` : null].filter(Boolean).join(" · ")}
          </p>
        </div>
      </div>
    </div>
  );
}
