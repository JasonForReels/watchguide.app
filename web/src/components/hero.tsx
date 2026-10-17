"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { Clapperboard, Info } from "lucide-react";
import { genreName } from "@/lib/catalog";
import { hrefOf, img, titleOf, typeOf, yearOf } from "@/lib/media";
import type { MediaItem } from "@/lib/types";
import { AutoTrailer, MuteButton, useAutoplayAllowed } from "./auto-trailer";

export interface HeroSlide {
  item: MediaItem;
  logo: string | null;
  /** YouTube key of the title's trailer, if it has one. */
  trailer: string | null;
}

/** Backdrop first, then the trailer, then a beat on the backdrop before the next slide (HeroCarouselView). */
type Phase = "backdrop" | "trailer" | "post";
const BACKDROP_MS = 2500;
const POST_MS = 1500;
const STILL_MS = 8000;
/** Give up on a trailer that hasn't started by then (blocked, region-locked, slow). */
const START_TIMEOUT_MS = 7000;

/**
 * Hero carousel at the top of Browse, laid out like the iOS one. Each slide shows its artwork,
 * then plays its trailer muted (with a shared mute toggle and a progress bar in place of the
 * dots) and moves on when it ends. Without a trailer, or with autoplay off, slides advance
 * every 8s and pause on hover.
 */
export function Hero({ slides }: { slides: HeroSlide[] }) {
  const [index, setIndex] = useState(0);
  const [paused, setPaused] = useState(false);
  const [phase, setPhase] = useState<Phase>("backdrop");
  const [started, setStarted] = useState(false);
  const [progress, setProgress] = useState(0);
  const allowed = useAutoplayAllowed("autoPlayTrailers");
  const trailer = slides[index]?.trailer;
  const autoplay = allowed && !!trailer;

  const goTo = useCallback((i: number) => {
    setIndex(i);
    setPhase("backdrop");
    setStarted(false);
    setProgress(0);
  }, []);
  const next = useCallback(() => goTo((index + 1) % Math.max(slides.length, 1)), [goTo, index, slides.length]);

  useEffect(() => {
    if (slides.length === 0) return;
    if (phase === "backdrop") {
      if (autoplay) {
        const t = setTimeout(() => setPhase("trailer"), BACKDROP_MS);
        return () => clearTimeout(t);
      }
      if (paused || slides.length < 2) return;
      const t = setTimeout(next, STILL_MS);
      return () => clearTimeout(t);
    }
    if (phase === "trailer" && !started) {
      const t = setTimeout(next, START_TIMEOUT_MS);
      return () => clearTimeout(t);
    }
    if (phase === "post") {
      const t = setTimeout(next, POST_MS);
      return () => clearTimeout(t);
    }
  }, [phase, autoplay, paused, started, next, slides.length]);

  if (!slides.length) return null;
  const { item, logo } = slides[index];
  const playing = phase === "trailer" && started;
  const type = typeOf(item);
  const title = titleOf(item);
  const genres = (item.genre_ids ?? []).slice(0, 3).map(genreName).filter(Boolean);

  return (
    <section
      className="relative h-[58vh] min-h-[420px] max-h-[720px] w-full overflow-hidden md:h-[64vh]"
      onMouseEnter={() => setPaused(true)}
      onMouseLeave={() => setPaused(false)}
      aria-roledescription="carousel"
      aria-label="Trending now"
    >
      {slides.map((s, i) => (
        // eslint-disable-next-line @next/next/no-img-element
        <img
          key={s.item.id}
          src={img(s.item.backdrop_path, "w1280") ?? ""}
          alt=""
          className={`absolute inset-0 h-full w-full object-cover transition-opacity duration-1000 ${i === index ? "opacity-100" : "opacity-0"}`}
          style={{ transform: i === index ? "scale(1.04)" : "scale(1)", transition: "opacity 1s, transform 9s linear" }}
          fetchPriority={i === 0 ? "high" : "low"}
        />
      ))}
      {autoplay && trailer && (
        <AutoTrailer
          key={`${item.id}-${trailer}`}
          videoKey={trailer}
          active={phase === "trailer"}
          onPlaying={() => setStarted(true)}
          onProgress={setProgress}
          onEnded={() => setPhase("post")}
          onError={next}
        />
      )}
      <div className="absolute inset-0 bg-gradient-to-t from-bg via-bg/30 to-transparent" />
      <div className="absolute inset-0 bg-gradient-to-r from-black/60 via-black/10 to-transparent" />

      <div key={item.id} className="rise absolute inset-x-0 bottom-0 px-5 pb-12 text-white sm:px-8">
        {logo ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={img(logo, "w500") ?? ""} alt={title} className="mb-3 max-h-24 max-w-[min(62%,380px)] object-contain object-left drop-shadow-2xl sm:max-h-28" />
        ) : (
          <h2 className="mb-2 max-w-2xl font-display text-4xl font-bold drop-shadow-lg sm:text-5xl">{title}</h2>
        )}
        <p className="mb-3 flex flex-wrap items-center gap-x-2 text-[13px] font-medium tracking-[0.12em] text-white/85 sm:text-sm">
          <span>{type === "tv" ? "SERIES" : "MOVIE"}</span>
          {yearOf(item) && <><span aria-hidden>·</span><span className="tracking-normal">{yearOf(item)}</span></>}
          {item.vote_average ? <><span aria-hidden>·</span><span className="tracking-normal">★ {item.vote_average.toFixed(1)}</span></> : null}
          {genres.length > 0 && <span className="hidden tracking-normal md:inline">· {genres.slice(0, 2).join(", ")}</span>}
        </p>
        <p className="mb-4 hidden max-w-md text-[17px] leading-snug text-white/85 md:line-clamp-2">{item.overview}</p>
        <Link href={hrefOf(type, item.id)} className="glass-clear press inline-flex items-center gap-2 rounded-full px-3.5 py-1.5 text-[15px] font-medium">
          <Info className="size-[18px]" /> More Details
        </Link>
      </div>

      <div className="absolute inset-x-0 bottom-14 flex items-center justify-center gap-1.5 max-md:bottom-[calc(3rem+6px)] max-md:justify-end max-md:pr-[22%]">
        {playing ? (
          <div className="h-1 w-20 overflow-hidden rounded-full bg-white/30" role="progressbar" aria-label="Trailer progress" aria-valuenow={Math.round(progress * 100)}>
            <div className="h-full rounded-full bg-white transition-[width] duration-300 ease-linear" style={{ width: `${progress * 100}%` }} />
          </div>
        ) : (
          slides.map((s, i) => (
            <button
              key={s.item.id}
              type="button"
              onClick={() => goTo(i)}
              aria-label={`Show ${titleOf(s.item)}`}
              aria-current={i === index}
              className={`h-1 rounded-full transition-all ${i === index ? "w-5 bg-white" : "w-1 bg-white/45 hover:bg-white/70"}`}
            />
          ))
        )}
      </div>
      {phase === "trailer" && <MuteButton className="absolute right-4 bottom-10 sm:right-8 md:bottom-12" />}
    </section>
  );
}

/** "Can't Decide?" card under the hero that leads into Tonight, as on iOS. */
export function CantDecide({ posters }: { posters: (string | null | undefined)[] }) {
  const art = posters.filter(Boolean).slice(0, 3) as string[];
  return (
    <section className="px-4 sm:px-8">
      <Link href="/tonight" className="press flex items-center gap-4 overflow-hidden rounded-[26px] bg-surface p-5 sm:px-6">
        <div className="min-w-0 flex-1">
          <h2 className="text-[22px] leading-7 font-semibold">Can&apos;t Decide?</h2>
          <p className="mt-1 text-[17px] leading-snug text-muted md:text-[15px]">Tonight shows you one pick at a time. Swipe until something clicks.</p>
          <p className="mt-3 inline-flex items-center gap-2 text-[17px] font-semibold text-accent">
            <Clapperboard className="size-5" /> Open Tonight
          </p>
        </div>
        <div className="relative h-28 w-32 shrink-0 sm:h-24 sm:w-28">
          {art.map((p, i) => (
            // eslint-disable-next-line @next/next/no-img-element
            <img
              key={p}
              src={img(p, "w185") ?? ""}
              alt=""
              className="absolute top-0 h-full w-[60%] rounded-lg object-cover shadow-xl ring-1 ring-white/10"
              style={{ left: `${i * 20}%`, zIndex: 3 - i, transform: `rotate(${(i - 1) * 4}deg) scale(${1 - i * 0.06})` }}
            />
          ))}
        </div>
      </Link>
    </section>
  );
}
