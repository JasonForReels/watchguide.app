"use client";

import Link from "next/link";
import { useCallback, useEffect, useRef, useState } from "react";
import { Bookmark, Heart, Info, Pause, Play, Volume2, VolumeX } from "lucide-react";
import { ENDED, loadYouTube, PLAYING, type YTPlayer } from "@/components/auto-trailer";
import { hrefOf, img, titleOf, toSaved, yearOf } from "@/lib/media";
import { actions, useHydrated, useStore } from "@/lib/store";
import type { MediaItem, MediaType } from "@/lib/types";

export interface Pop {
  item: MediaItem;
  type: MediaType;
  videoKey: string;
  clipName: string;
}

/** Two taps closer than this are a double tap. */
const DOUBLE_TAP_MS = 280;
/** Holding this long pauses until release. */
const HOLD_MS = 320;
/** Movement that turns a tap into a scroll. */
const TAP_SLOP = 10;

/**
 * Vertical clip feed with Instagram Reels behaviour: one clip per swipe (no flinging past
 * several), tap to pause, double-tap to like, press and hold to pause until release, a
 * scrubbable progress bar, looping, and a mute choice that carries from clip to clip.
 * Only the clip on screen gets a player, like ClipsView.
 */
export function PopsFeed({ pops }: { pops: Pop[] }) {
  const [active, setActive] = useState(0);
  const scroller = useRef<HTMLDivElement>(null);
  const refs = useRef<(HTMLElement | null)[]>([]);
  const muted = useStore((s) => s.settings.trailersMuted);
  const toggleMute = useCallback(() => actions.updateSettings({ trailersMuted: !muted }), [muted]);

  useEffect(() => {
    const io = new IntersectionObserver(
      (entries) => {
        for (const e of entries) if (e.isIntersecting) setActive(Number((e.target as HTMLElement).dataset.index));
      },
      { threshold: 0.6 },
    );
    refs.current.forEach((el) => el && io.observe(el));
    return () => io.disconnect();
  }, [pops.length]);

  const go = useCallback((dir: 1 | -1) => {
    const el = scroller.current;
    if (el) el.scrollBy({ top: dir * el.clientHeight, behavior: "smooth" });
  }, []);

  // Desktop: arrow keys / J K move one clip, M mutes.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.target instanceof Element && e.target.closest("input,textarea,select")) return;
      if (e.key === "ArrowDown" || e.key === "j") { e.preventDefault(); go(1); }
      else if (e.key === "ArrowUp" || e.key === "k") { e.preventDefault(); go(-1); }
      else if (e.key === "m") toggleMute();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [go, toggleMute]);

  if (!pops.length) {
    return <p className="px-4 pt-24 text-center text-muted">No clips right now. Check back soon.</p>;
  }

  return (
    <div
      ref={scroller}
      className="rail fixed inset-0 z-0 snap-y snap-mandatory overflow-y-auto overscroll-contain bg-black"
    >
      {pops.map((p, i) => (
        <section
          key={`${p.type}-${p.item.id}`}
          ref={(el) => { refs.current[i] = el; }}
          data-index={i}
          // snap-always: one clip per swipe, however hard the flick, as on Reels.
          className="relative h-dvh snap-start snap-always overflow-hidden"
        >
          <Reel pop={p} active={i === active} near={Math.abs(i - active) <= 1} muted={muted} onToggleMute={toggleMute} />
        </section>
      ))}
    </div>
  );
}

function Reel({ pop, active, near, muted, onToggleMute }: { pop: Pop; active: boolean; near: boolean; muted: boolean; onToggleMute: () => void }) {
  const key = `${pop.type}-${pop.item.id}`;
  const hydrated = useHydrated();
  const liked = useStore((s) => s.lists.liked.some((i) => i.key === key));
  const saved = useStore((s) => s.lists.want.some((i) => i.key === key));
  const item = toSaved(pop.item, pop.type);

  const [paused, setPaused] = useState(false);
  const pausedRef = useRef(paused);
  useEffect(() => { pausedRef.current = paused; }, [paused]);
  const [held, setHeld] = useState(false);
  const [progress, setProgress] = useState(0);
  const [flash, setFlash] = useState<"play" | "pause" | null>(null);
  const [hearts, setHearts] = useState<{ id: number; x: number; y: number }[]>([]);
  const seek = useRef<((f: number) => void) | null>(null);

  // A clip always starts playing when it scrolls into view.
  const [wasActive, setWasActive] = useState(active);
  if (active !== wasActive) {
    setWasActive(active);
    if (active) setPaused(false);
  }

  const gesture = useRef<{ x: number; y: number; t: number; hold: number; moved: boolean } | null>(null);
  const lastTap = useRef(0);
  const singleTap = useRef(0);

  const onPointerDown = (e: React.PointerEvent) => {
    gesture.current = {
      x: e.clientX,
      y: e.clientY,
      t: Date.now(),
      moved: false,
      hold: window.setTimeout(() => setHeld(true), HOLD_MS),
    };
  };
  const onPointerMove = (e: React.PointerEvent) => {
    const g = gesture.current;
    if (g && !g.moved && Math.hypot(e.clientX - g.x, e.clientY - g.y) > TAP_SLOP) {
      g.moved = true;
      window.clearTimeout(g.hold);
    }
  };
  const onPointerUp = (e: React.PointerEvent) => {
    const g = gesture.current;
    gesture.current = null;
    if (!g) return;
    window.clearTimeout(g.hold);
    if (held) { setHeld(false); return; }
    if (g.moved) return;

    const now = Date.now();
    if (now - lastTap.current < DOUBLE_TAP_MS) {
      // Double tap: like, with a heart where you tapped. Never unlikes, same as Instagram.
      window.clearTimeout(singleTap.current);
      lastTap.current = 0;
      if (!liked) actions.toggle("liked", item);
      const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
      const id = now;
      setHearts((h) => [...h, { id, x: e.clientX - rect.left, y: e.clientY - rect.top }]);
      window.setTimeout(() => setHearts((h) => h.filter((x) => x.id !== id)), 900);
      return;
    }
    lastTap.current = now;
    singleTap.current = window.setTimeout(() => {
      const nowPaused = !pausedRef.current;
      setPaused(nowPaused);
      setFlash(nowPaused ? "pause" : "play");
      window.setTimeout(() => setFlash(null), 600);
    }, DOUBLE_TAP_MS);
  };

  const playing = active && !paused && !held;
  const circle = "glass-clear press grid size-12 place-items-center rounded-full";

  return (
    <>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={img(pop.item.backdrop_path, "w780") ?? ""} alt="" loading={near ? "eager" : "lazy"} className="absolute inset-0 h-full w-full scale-125 object-cover opacity-60 blur-2xl" />
      <div className="absolute inset-0 bg-black/40" />

      <div className="absolute inset-0 grid place-items-center">
        <div className="relative aspect-video w-full max-w-5xl overflow-hidden bg-black md:rounded-3xl md:shadow-2xl">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={img(pop.item.backdrop_path, "w1280") ?? ""} alt="" loading={near ? "eager" : "lazy"} className="absolute inset-0 h-full w-full object-cover" />
          {active && (
            <ReelPlayer videoKey={pop.videoKey} title={titleOf(pop.item)} playing={playing} muted={muted} onProgress={setProgress} seekRef={seek} />
          )}
        </div>
      </div>

      {/* Gesture surface: tap, double tap, hold. Vertical swipes fall through to the scroller. */}
      <div
        className="absolute inset-0 touch-pan-y select-none"
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={() => { if (gesture.current) window.clearTimeout(gesture.current.hold); gesture.current = null; setHeld(false); }}
        onContextMenu={(e) => e.preventDefault()}
      >
        {flash && (
          <span className="pointer-events-none absolute top-1/2 left-1/2 grid size-20 -translate-x-1/2 -translate-y-1/2 animate-[pop-flash_0.6s_ease-out_forwards] place-items-center rounded-full bg-black/40 text-white backdrop-blur">
            {flash === "pause" ? <Pause className="size-9 fill-current" /> : <Play className="size-9 fill-current" />}
          </span>
        )}
        {paused && !flash && (
          <span className="pointer-events-none absolute top-1/2 left-1/2 grid size-20 -translate-x-1/2 -translate-y-1/2 place-items-center rounded-full bg-black/40 text-white backdrop-blur">
            <Play className="size-9 fill-current" />
          </span>
        )}
        {hearts.map((h) => (
          <Heart
            key={h.id}
            className="pointer-events-none absolute size-24 -translate-x-1/2 -translate-y-1/2 animate-[pop-heart_0.9s_ease-out_forwards] fill-[#ff375f] text-[#ff375f] drop-shadow-xl"
            style={{ left: h.x, top: h.y }}
          />
        ))}
      </div>

      {/* Info and actions fade back while you hold, like Reels' clean view. */}
      <div className={`pointer-events-none absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/85 via-black/40 to-transparent px-5 pt-24 pb-[calc(max(env(safe-area-inset-bottom),12px)+96px)] text-white transition-opacity duration-300 md:px-10 md:pb-14 ${held ? "opacity-0" : "opacity-100"}`}>
        <div className="flex items-end gap-4">
          <div className="pointer-events-auto min-w-0 flex-1">
            <p className="text-[13px] font-semibold tracking-wide text-white/70 uppercase">{pop.type === "tv" ? "Series" : "Movie"} · {yearOf(pop.item)}</p>
            <h2 className="mt-0.5 line-clamp-2 text-[24px] leading-tight font-bold">{titleOf(pop.item)}</h2>
            <p className="mt-1 line-clamp-1 text-[15px] text-white/70">{pop.clipName}</p>
            <Link href={hrefOf(pop.type, pop.item.id)} className="glass-clear press mt-3 inline-flex items-center gap-2 rounded-full px-4 py-2 text-[15px] font-medium">
              <Info className="size-[18px]" /> More Details
            </Link>
          </div>
          <div className="pointer-events-auto flex shrink-0 flex-col gap-3">
            <button type="button" aria-label={muted ? "Unmute" : "Mute"} onClick={onToggleMute} className={circle}>
              {hydrated && !muted ? <Volume2 className="size-[22px]" /> : <VolumeX className="size-[22px]" />}
            </button>
            <button type="button" aria-label="Like" aria-pressed={hydrated && liked} onClick={() => actions.toggle("liked", item)} className={circle}>
              <Heart className={`size-[22px] ${hydrated && liked ? "fill-[#ff375f] text-[#ff375f]" : ""}`} />
            </button>
            <button type="button" aria-label="Save to watchlist" aria-pressed={hydrated && saved} onClick={() => actions.toggle("want", item)} className={circle}>
              <Bookmark className={`size-[22px] ${hydrated && saved ? "fill-current" : ""}`} />
            </button>
          </div>
        </div>
      </div>

      {/* Scrubbable progress line along the bottom edge of the clip area. */}
      {active && (
        <div
          role="slider"
          aria-label="Clip position"
          aria-valuemin={0}
          aria-valuemax={100}
          aria-valuenow={Math.round(progress * 100)}
          tabIndex={0}
          className="group absolute inset-x-0 bottom-[calc(max(env(safe-area-inset-bottom),12px)+80px)] h-5 cursor-pointer touch-none md:bottom-2"
          onPointerDown={(e) => {
            const el = e.currentTarget;
            el.setPointerCapture(e.pointerId);
            const at = (x: number) => {
              const r = el.getBoundingClientRect();
              const f = Math.min(1, Math.max(0, (x - r.left) / r.width));
              setProgress(f);
              seek.current?.(f);
            };
            at(e.clientX);
            const move = (ev: PointerEvent) => at(ev.clientX);
            const up = () => { el.removeEventListener("pointermove", move); el.removeEventListener("pointerup", up); };
            el.addEventListener("pointermove", move);
            el.addEventListener("pointerup", up);
          }}
        >
          <div className="absolute inset-x-0 bottom-2 h-0.5 bg-white/25 transition-[height] group-hover:h-1 group-active:h-1.5">
            <div className="h-full bg-white" style={{ width: `${progress * 100}%` }} />
          </div>
        </div>
      )}
    </>
  );
}

/** The YouTube player for the clip on screen: loops, follows play/pause and mute, reports progress. */
function ReelPlayer({ videoKey, title, playing, muted, onProgress, seekRef }: {
  videoKey: string;
  title: string;
  playing: boolean;
  muted: boolean;
  onProgress: (f: number) => void;
  seekRef: React.RefObject<((f: number) => void) | null>;
}) {
  const host = useRef<HTMLDivElement>(null);
  const player = useRef<YTPlayer | null>(null);
  const [ready, setReady] = useState(false);
  const [visible, setVisible] = useState(false);
  const state = useRef({ playing, muted, onProgress });
  useEffect(() => { state.current = { playing, muted, onProgress }; });

  useEffect(() => {
    let cancelled = false;
    const mount = document.createElement("div");
    host.current?.appendChild(mount);
    loadYouTube().then((YT) => {
      if (cancelled) return;
      const p = new YT.Player(mount, {
        host: "https://www.youtube-nocookie.com",
        videoId: videoKey,
        playerVars: { autoplay: 1, mute: 1, controls: 0, playsinline: 1, rel: 0, modestbranding: 1, iv_load_policy: 3, disablekb: 1, fs: 0 },
        events: {
          onReady: () => {
            if (!state.current.muted) p.unMute();
            if (state.current.playing) p.playVideo(); else p.pauseVideo();
            setReady(true);
          },
          onStateChange: (e: { data: number }) => {
            if (e.data === PLAYING) window.setTimeout(() => setVisible(true), 350);
            // Loop, as Reels do.
            if (e.data === ENDED) { p.seekTo(0, true); p.playVideo(); }
          },
        },
      });
      player.current = p;
      seekRef.current = (f: number) => {
        const d = p.getDuration?.() ?? 0;
        if (d > 0) p.seekTo(f * d, true);
      };
    });
    return () => {
      cancelled = true;
      player.current?.destroy();
      player.current = null;
      seekRef.current = null;
      mount.remove();
    };
  }, [videoKey, seekRef]);

  useEffect(() => {
    const p = player.current;
    if (!ready || !p) return;
    if (playing) p.playVideo(); else p.pauseVideo();
  }, [playing, ready]);

  useEffect(() => {
    const p = player.current;
    if (!ready || !p) return;
    if (muted) p.mute(); else p.unMute();
  }, [muted, ready]);

  useEffect(() => {
    if (!ready) return;
    const t = window.setInterval(() => {
      const p = player.current;
      const d = p?.getDuration?.() ?? 0;
      if (p && d > 0) state.current.onProgress(p.getCurrentTime() / d);
    }, 200);
    return () => window.clearInterval(t);
  }, [ready]);

  return (
    <div
      ref={host}
      title={title}
      className={`pointer-events-none absolute inset-0 transition-opacity duration-500 [&>iframe]:h-full [&>iframe]:w-full ${visible ? "opacity-100" : "opacity-0"}`}
    />
  );
}
