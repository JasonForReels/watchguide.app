"use client";

import { useEffect, useRef, useState } from "react";
import { Volume2, VolumeX } from "lucide-react";
import { actions, useHydrated, useStore } from "@/lib/store";

/** The slice of the YouTube IFrame API this app uses. */
export interface YTPlayer {
  playVideo(): void;
  pauseVideo(): void;
  mute(): void;
  unMute(): void;
  getCurrentTime(): number;
  getDuration(): number;
  seekTo(seconds: number, allowSeekAhead: boolean): void;
  destroy(): void;
}
interface YTNamespace {
  Player: new (el: HTMLElement, opts: Record<string, unknown>) => YTPlayer;
}
declare global {
  interface Window {
    YT?: YTNamespace;
    onYouTubeIframeAPIReady?: () => void;
  }
}

let apiPromise: Promise<YTNamespace> | null = null;
/** Loads the YouTube IFrame API once. */
export function loadYouTube(): Promise<YTNamespace> {
  if (window.YT?.Player) return Promise.resolve(window.YT);
  apiPromise ??= new Promise((resolve) => {
    const prev = window.onYouTubeIframeAPIReady;
    window.onYouTubeIframeAPIReady = () => {
      prev?.();
      resolve(window.YT!);
    };
    const s = document.createElement("script");
    s.src = "https://www.youtube.com/iframe_api";
    s.async = true;
    document.head.appendChild(s);
  });
  return apiPromise;
}

export const PLAYING = 1;
export const ENDED = 0;

/** Whether trailers may autoplay at all: the setting, and the viewer's reduced-motion choice. */
export function useAutoplayAllowed(setting: "autoPlayTrailers" | "showTrailersInDetails") {
  const hydrated = useHydrated();
  const on = useStore((s) => s.settings[setting]);
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    const mq = matchMedia("(prefers-reduced-motion: reduce)");
    const update = () => setReduced(mq.matches);
    update();
    mq.addEventListener("change", update);
    return () => mq.removeEventListener("change", update);
  }, []);
  return hydrated && on && !reduced;
}

/**
 * A trailer that plays muted behind hero artwork, cropped to fill its stage like the iOS
 * HeroCarouselView. It stays invisible until YouTube actually starts playing (so its title
 * card never flashes), pauses while off-screen or in a background tab, and reports progress
 * and the end so the carousel can move on.
 */
export function AutoTrailer({
  videoKey,
  active,
  onEnded,
  onProgress,
  onPlaying,
  onError,
}: {
  videoKey: string;
  active: boolean;
  onEnded?: () => void;
  onProgress?: (fraction: number) => void;
  onPlaying?: () => void;
  onError?: () => void;
}) {
  const host = useRef<HTMLDivElement>(null);
  const player = useRef<YTPlayer | null>(null);
  const [visible, setVisible] = useState(false);
  const [onScreen, setOnScreen] = useState(true);
  const muted = useStore((s) => s.settings.trailersMuted);
  const cbs = useRef({ onEnded, onProgress, onPlaying, onError });
  useEffect(() => { cbs.current = { onEnded, onProgress, onPlaying, onError }; });
  const mutedRef = useRef(muted);
  useEffect(() => { mutedRef.current = muted; }, [muted]);

  // Create the player for this video.
  useEffect(() => {
    let cancelled = false;
    let timer = 0;
    const mount = document.createElement("div");
    host.current?.appendChild(mount);
    loadYouTube().then((YT) => {
      if (cancelled) return;
      player.current = new YT.Player(mount, {
        host: "https://www.youtube-nocookie.com",
        videoId: videoKey,
        playerVars: { autoplay: 0, mute: 1, controls: 0, playsinline: 1, rel: 0, modestbranding: 1, iv_load_policy: 3, disablekb: 1, fs: 0 },
        events: {
          onReady: () => {
            if (!mutedRef.current) player.current?.unMute();
          },
          onStateChange: (e: { data: number }) => {
            if (e.data === PLAYING) {
              // A beat after playback starts, once YouTube's own overlay is gone.
              window.clearTimeout(timer);
              timer = window.setTimeout(() => setVisible(true), 450);
              cbs.current.onPlaying?.();
            } else if (e.data === ENDED) {
              setVisible(false);
              cbs.current.onEnded?.();
            }
          },
          onError: () => cbs.current.onError?.(),
        },
      });
    });
    return () => {
      cancelled = true;
      window.clearTimeout(timer);
      player.current?.destroy();
      player.current = null;
      mount.remove();
      setVisible(false);
    };
  }, [videoKey]);

  // Pause when scrolled away or the tab is hidden, as iOS does when the carousel leaves the screen.
  useEffect(() => {
    const el = host.current;
    if (!el) return;
    const io = new IntersectionObserver(([e]) => setOnScreen(e.isIntersecting), { threshold: 0.25 });
    io.observe(el);
    const vis = () => setOnScreen(!document.hidden && el.getBoundingClientRect().bottom > 0);
    document.addEventListener("visibilitychange", vis);
    return () => { io.disconnect(); document.removeEventListener("visibilitychange", vis); };
  }, []);

  const shouldPlay = active && onScreen;
  useEffect(() => {
    let tries = 0;
    // The player may still be loading; retry briefly until its methods exist.
    const t = window.setInterval(() => {
      const p = player.current;
      if (p && typeof p.playVideo === "function") {
        if (shouldPlay) p.playVideo(); else p.pauseVideo();
        window.clearInterval(t);
      } else if (++tries > 40) window.clearInterval(t);
    }, 150);
    return () => window.clearInterval(t);
  }, [shouldPlay, videoKey]);

  useEffect(() => {
    const p = player.current;
    if (!p || typeof p.mute !== "function") return;
    if (muted) p.mute(); else p.unMute();
  }, [muted]);

  useEffect(() => {
    if (!shouldPlay || !visible) return;
    const t = window.setInterval(() => {
      const p = player.current;
      const d = p?.getDuration?.() ?? 0;
      if (p && d > 0) cbs.current.onProgress?.(Math.min(1, p.getCurrentTime() / d));
    }, 250);
    return () => window.clearInterval(t);
  }, [shouldPlay, visible]);

  return (
    <div
      aria-hidden
      className={`pointer-events-none absolute inset-0 overflow-hidden transition-opacity duration-700 ${visible && active ? "opacity-100" : "opacity-0"}`}
      style={{ containerType: "size" }}
    >
      {/* Oversized and centred so a 16:9 video fills any stage and YouTube's chrome falls outside it. */}
      <div
        ref={host}
        className="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2 [&>iframe]:h-full [&>iframe]:w-full"
        style={{ width: "max(118cqw, 210cqh)", height: "max(66.4cqw, 118cqh)" }}
      />
    </div>
  );
}

/** Glass mute toggle shared by every autoplaying trailer, like HeroCarouselMuteManager. */
export function MuteButton({ className = "" }: { className?: string }) {
  const hydrated = useHydrated();
  const muted = useStore((s) => s.settings.trailersMuted);
  return (
    <button
      type="button"
      aria-label={muted ? "Unmute trailer" : "Mute trailer"}
      aria-pressed={hydrated && !muted}
      onClick={() => actions.updateSettings({ trailersMuted: !muted })}
      className={`glass-clear press grid size-10 place-items-center rounded-full ${className}`}
    >
      {hydrated && !muted ? <Volume2 className="size-5" /> : <VolumeX className="size-5" />}
    </button>
  );
}
