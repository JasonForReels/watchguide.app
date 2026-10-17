"use client";

import { useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { Bookmark, Check, Heart, Play, Share, X } from "lucide-react";
import { toSaved } from "@/lib/media";
import { actions, useHydrated, useStore } from "@/lib/store";
import type { MediaType, TitleDetails } from "@/lib/types";
import { AutoTrailer, MuteButton, useAutoplayAllowed } from "./auto-trailer";
import { AddToList } from "./list-buttons";
import { TrailerModal } from "./trailer";

/** Top-left close button of the iOS detail sheet. */
export function CloseButton() {
  const router = useRouter();
  return (
    <button
      type="button"
      aria-label="Close"
      onClick={() => (window.history.length > 1 ? router.back() : router.push("/"))}
      className="glass-clear press fixed top-[max(env(safe-area-inset-top),16px)] left-4 z-40 grid size-11 place-items-center rounded-full sm:left-6"
    >
      <X className="size-6" strokeWidth={2.4} />
    </button>
  );
}

const ordinal = (n: number) => {
  const s = ["th", "st", "nd", "rd"];
  const v = n % 100;
  return `${n}${s[(v - 20) % 10] ?? s[v] ?? s[0]}`;
};

/** Watched capsule, bookmark, and the Like / Lists / Share row from MediaDetailView. */
export function DetailActions({ item, type }: { item: TitleDetails; type: MediaType }) {
  const key = `${type}-${item.id}`;
  const hydrated = useHydrated();
  const want = useStore((s) => s.lists.want.some((i) => i.key === key));
  const liked = useStore((s) => s.lists.liked.some((i) => i.key === key));
  const watchedList = useStore((s) => s.lists.watched);
  const watched = watchedList.find((i) => i.key === key);
  const saved = toSaved(item, type);
  const [shared, setShared] = useState(false);

  // "Your 41st this year." counts titles finished this calendar year, up to this one.
  const year = new Date().getFullYear();
  const nth = watched && new Date(watched.addedAt).getFullYear() === year
    ? watchedList.filter((i) => new Date(i.addedAt).getFullYear() === year && i.addedAt <= watched.addedAt).length
    : 0;

  const share = async () => {
    const url = window.location.href;
    const title = item.title ?? item.name ?? "WatchGuide";
    try {
      if (navigator.share) await navigator.share({ title, url });
      else {
        await navigator.clipboard.writeText(url);
        setShared(true);
        setTimeout(() => setShared(false), 1600);
      }
    } catch {}
  };

  const doneLabel = type === "tv" ? "Finished" : "Watched";

  return (
    <div className="space-y-3">
      <div className="flex items-center gap-2.5">
        <button
          type="button"
          aria-pressed={hydrated && !!watched}
          onClick={() => actions.toggle("watched", saved)}
          className="glass-clear press flex h-14 flex-1 items-center justify-center gap-2.5 rounded-full text-[19px] font-semibold"
        >
          {hydrated && watched ? <><Check className="size-6" strokeWidth={2.8} /> {doneLabel}</> : <>Mark as {doneLabel}</>}
        </button>
        <button
          type="button"
          aria-label={want ? "Remove from watchlist" : "Add to watchlist"}
          aria-pressed={hydrated && want}
          onClick={() => actions.toggle("want", saved)}
          className="glass-clear press grid size-14 shrink-0 place-items-center rounded-full"
        >
          <Bookmark className={`size-6 ${hydrated && want ? "fill-current" : ""}`} strokeWidth={2.2} />
        </button>
      </div>
      <p className="h-5 text-center text-[15px] text-text/60">{hydrated && nth > 0 ? `Your ${ordinal(nth)} this year.` : ""}</p>
      <div className="flex justify-center gap-6">
        <button type="button" aria-pressed={hydrated && liked} onClick={() => actions.toggle("liked", saved)} className="press flex w-16 flex-col items-center gap-1.5 text-[13px] font-medium text-text/80">
          <span className="glass-clear grid size-12 place-items-center rounded-full">
            <Heart className={`size-[22px] ${hydrated && liked ? "fill-[#ff375f] text-[#ff375f]" : ""}`} />
          </span>
          Like
        </button>
        <AddToList item={item} type={type} labeled />
        <button type="button" onClick={share} className="press flex w-16 flex-col items-center gap-1.5 text-[13px] font-medium whitespace-nowrap text-text/80">
          <span className="glass-clear grid size-12 place-items-center rounded-full"><Share className="size-[21px]" /></span>
          {shared ? "Copied" : "Share"}
        </button>
      </div>
    </div>
  );
}

/** Full-width Play Trailer bar. */
export function PlayTrailer({ videoKey, title }: { videoKey: string; title: string }) {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="glass-clear press flex h-14 w-full items-center justify-center gap-2.5 rounded-2xl text-[19px] font-semibold"
      >
        <Play className="size-5 fill-current" /> Play Trailer
      </button>
      {open && <TrailerModal videoKey={videoKey} title={title} onClose={() => setOpen(false)} />}
    </>
  );
}

/**
 * The title page header's auto-playing trailer (MediaDetailView's header section): starts a
 * moment after the page opens, fades over the backdrop, and steps aside when it ends.
 */
export function HeaderTrailer({ videoKey }: { videoKey: string }) {
  const allowed = useAutoplayAllowed("showTrailersInDetails");
  const [active, setActive] = useState(false);
  const [done, setDone] = useState(false);
  useEffect(() => {
    if (!allowed) return;
    const t = setTimeout(() => setActive(true), 1200);
    return () => clearTimeout(t);
  }, [allowed]);
  const playing = allowed && active && !done;
  useEffect(() => {
    // The title logo shrinks while the trailer plays (see title page).
    if (!playing) return;
    document.documentElement.dataset.trailer = "playing";
    return () => { delete document.documentElement.dataset.trailer; };
  }, [playing]);
  if (!allowed || done) return null;
  return (
    <>
      <div className="absolute inset-0 [mask-image:linear-gradient(to_bottom,black_50%,transparent)]">
        <AutoTrailer videoKey={videoKey} active={active} onEnded={() => setDone(true)} onError={() => setDone(true)} />
      </div>
      {active && <MuteButton className="fixed top-[max(env(safe-area-inset-top),16px)] right-4 z-40 size-11 sm:right-6" />}
    </>
  );
}
