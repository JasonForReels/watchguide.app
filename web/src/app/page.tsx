import { cacheLife } from "next/cache";
import { BackdropCard, PersonCard, PosterCard } from "@/components/cards";
import { BecauseYouLiked, Chapter, RankedRail, Spotlight, UpNextRail, WatchlistRail } from "@/components/browse-blocks";
import { CantDecide, Hero, type HeroSlide } from "@/components/hero";
import { Rail } from "@/components/rail";
import { HUBS } from "@/lib/catalog";
import { dedupe, typeOf } from "@/lib/media";
import { list, tmdbSafe } from "@/lib/tmdb";
import { comingToStreaming, leavingSoon } from "@/lib/streaming-soon";
import { pickTrailer } from "@/lib/media";
import type { MediaItem, Paged, Video } from "@/lib/types";
import Link from "next/link";

async function heroSlides(items: MediaItem[]): Promise<HeroSlide[]> {
  const picks = items.filter((i) => i.backdrop_path && i.overview).slice(0, 6);
  return Promise.all(
    picks.map(async (item) => {
      const [images, videos] = await Promise.all([
        tmdbSafe<{ logos: { file_path: string; iso_639_1: string | null }[] }>(`${typeOf(item)}/${item.id}/images`, { include_image_language: "en,null" }),
        tmdbSafe<{ results: Video[] }>(`${typeOf(item)}/${item.id}/videos`),
      ]);
      const logo = images?.logos.find((l) => l.iso_639_1 === "en") ?? images?.logos[0];
      return { item, logo: logo?.file_path ?? null, trailer: pickTrailer(videos?.results)?.key ?? null };
    }),
  );
}

export default async function BrowsePage() {
  "use cache";
  cacheLife("hours");

  const [trendingDay, trendingWeek, popularMovies, popularTV, nowPlaying, onAir, upcoming, topMovies, topTV, people, streamingSoon, leaving] =
    await Promise.all([
      list("trending/all/day"),
      list("trending/all/week"),
      list("movie/popular"),
      list("tv/popular"),
      list("movie/now_playing"),
      list("tv/on_the_air"),
      list("movie/upcoming"),
      list("movie/top_rated"),
      list("tv/top_rated"),
      tmdbSafe<Paged<{ id: number; name: string; profile_path: string | null; known_for_department?: string }>>("trending/person/week"),
      comingToStreaming(),
      leavingSoon(),
    ]);

  const trending = dedupe(trendingDay);
  const slides = await heroSlides(trending);
  const used = new Set(slides.map((s) => s.item.id));
  const spotlightA = trendingWeek.find((i) => i.backdrop_path && i.overview && !used.has(i.id) && i.media_type !== "person");
  const spotlightB = topTV.find((i) => i.backdrop_path && i.overview && (i.vote_count ?? 0) > 1000);

  return (
    <div className="space-y-10">
      <div className="space-y-6">
        <Hero slides={slides} />
        <CantDecide posters={trending.slice(6, 9).map((i) => i.poster_path)} />
      </div>

      <div className="space-y-9">
        <UpNextRail />
        <RankedRail title="Trending Today" items={trending.filter((i) => i.poster_path)} />
        <Rail title="Popular Films">
          {popularMovies.map((i) => <PosterCard key={i.id} item={i} type="movie" />)}
        </Rail>
        <Rail title="Popular Shows">
          {popularTV.map((i) => <PosterCard key={i.id} item={i} type="tv" />)}
        </Rail>
        <WatchlistRail />
      </div>

      {spotlightA && <Spotlight item={spotlightA} eyebrow="Everyone's watching this week" />}

      <div className="space-y-9">
        <Chapter label="Fresh" title="New this week" />
        <Rail title="In Cinemas" gap="gap-4">
          {nowPlaying.filter((i) => i.backdrop_path).map((i) => <BackdropCard key={i.id} item={i} type="movie" />)}
        </Rail>
        <Rail title="New Episodes" subtitle="Shows airing this week">
          {onAir.filter((i) => i.poster_path).map((i) => <PosterCard key={i.id} item={i} type="tv" />)}
        </Rail>
        <Rail title="Coming Soon" href="/calendar">
          {upcoming.map((i) => <PosterCard key={i.id} item={i} type="movie" />)}
        </Rail>
        {streamingSoon.length > 0 && (
          <Rail title="Coming Soon to Streaming" subtitle="Movies and new series landing in the next two months">
            {streamingSoon.map((i) => <PosterCard key={i.id} item={i} type={typeOf(i)} />)}
          </Rail>
        )}
        {leaving.length > 0 && (
          <Rail title="Leaving Soon" subtitle="Going from the main services" gap="gap-4">
            {leaving.map((e) => (
              <div key={e.item.id} className="w-64 shrink-0 space-y-1.5 sm:w-72">
                <BackdropCard item={e.item} type={e.type} />
                <p className="px-1 text-[13px] font-semibold text-muted">
                  Leaves {new Date(e.leavesOn).toLocaleDateString(undefined, { month: "short", day: "numeric" })} · {e.service}
                </p>
              </div>
            ))}
          </Rail>
        )}
        <BecauseYouLiked />
      </div>

      {spotlightB && <Spotlight item={spotlightB} eyebrow="All-time great TV" />}

      <div className="space-y-9">
        <Chapter label="Canon" title="The best of the best" />
        <Rail title="Top Rated Films">
          {topMovies.map((i) => <PosterCard key={i.id} item={i} type="movie" />)}
        </Rail>
        <Rail title="Top Rated Shows">
          {topTV.map((i) => <PosterCard key={i.id} item={i} type="tv" />)}
        </Rail>
        {people && (
          <Rail title="Trending People" gap="gap-5">
            {people.results.filter((p) => p.profile_path).map((p) => (
              <PersonCard key={p.id} id={p.id} name={p.name} role={p.known_for_department} path={p.profile_path} />
            ))}
          </Rail>
        )}
        <Rail title="Studios & Networks" href="/hubs" gap="gap-3">
          {HUBS.map((h) => (
            <Link
              key={h.slug}
              href={`/hubs/${h.slug}`}
              className="frame grid h-24 w-44 shrink-0 place-items-center rounded-card border border-line bg-surface px-4 text-center font-display text-lg font-bold tracking-tight transition hover:-translate-y-0.5"
              style={{ backgroundImage: `radial-gradient(120% 120% at 0% 0%, ${h.color}33, transparent 60%)` }}
            >
              {h.name}
            </Link>
          ))}
        </Rail>
      </div>
    </div>
  );
}
