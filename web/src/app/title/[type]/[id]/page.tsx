import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { Briefcase, Clock, DollarSign, Film, Globe, ShieldCheck, Star } from "lucide-react";
import { PersonCard, PosterCard } from "@/components/cards";
import { SeasonTracker } from "@/components/episodes";
import { CloseButton, DetailActions, HeaderTrailer, PlayTrailer } from "@/components/detail";
import { StarRating } from "@/components/list-buttons";
import { Rail, RailSkeleton } from "@/components/rail";
import { WhereToWatch } from "@/components/where-to-watch";
import { img, keyOf, pickTrailer, runtimeLabel, titleOf, toSaved, yearOf, formatDate } from "@/lib/media";
import { getSeason, getTitle } from "@/lib/tmdb";
import type { MediaType, SeasonDetails, TitleDetails } from "@/lib/types";

type Props = PageProps<"/title/[type]/[id]">;

async function load(params: Props["params"]) {
  const { type, id } = await params;
  if ((type !== "movie" && type !== "tv") || !/^\d+$/.test(id)) notFound();
  try {
    return { type: type as MediaType, data: await getTitle(type, Number(id)) };
  } catch {
    notFound();
  }
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { data } = await load(params);
  return {
    title: `${titleOf(data)}${yearOf(data) ? ` (${yearOf(data)})` : ""}`,
    description: data.overview,
    openGraph: { images: data.backdrop_path ? [img(data.backdrop_path, "w1280")!] : [] },
  };
}


/** US certificate (PG-13, TV-MA) from release dates or content ratings. */
function certificate(data: TitleDetails, type: MediaType): string | null {
  if (type === "movie") {
    const us = data.release_dates?.results.find((r) => r.iso_3166_1 === "US");
    return us?.release_dates.find((d) => d.certification)?.certification ?? null;
  }
  return data.content_ratings?.results.find((r) => r.iso_3166_1 === "US")?.rating || null;
}

const money = (n?: number) => (n ? `$${(n / 1_000_000).toFixed(n >= 1e8 ? 0 : 1)}M` : null);

function Facts({ data, type }: { data: TitleDetails; type: MediaType }) {
  const directors = data.credits?.crew.filter((c) => c.job === "Director").slice(0, 2) ?? [];
  const writers = data.credits?.crew.filter((c) => c.job === "Screenplay" || c.job === "Writer" || c.job === "Creator").slice(0, 3) ?? [];
  const rows: [string, React.ReactNode][] = [];
  if (directors.length) rows.push(["Director", directors.map((d) => <Link key={d.id} href={`/person/${d.id}`} className="hover:text-accent">{d.name}</Link>).reduce<React.ReactNode[]>((a, n, i) => (i ? [...a, ", ", n] : [n]), [])]);
  if (writers.length) rows.push(["Writing", writers.map((w) => w.name).join(", ")]);
  if (data.status) rows.push(["Status", data.status]);
  if (type === "movie") {
    rows.push(["Released", formatDate(data.release_date)]);
    if (money(data.budget)) rows.push(["Budget", money(data.budget)]);
    if (money(data.revenue)) rows.push(["Box office", money(data.revenue)]);
  } else {
    rows.push(["First aired", formatDate(data.first_air_date)]);
    if (data.next_episode_to_air) rows.push(["Next episode", `S${data.next_episode_to_air.season_number} E${data.next_episode_to_air.episode_number} · ${formatDate(data.next_episode_to_air.air_date)}`]);
    if (data.networks?.length) rows.push(["Network", data.networks.map((n) => n.name).join(", ")]);
  }
  if (data.production_companies?.length) rows.push(["Studio", data.production_companies.slice(0, 2).map((c) => c.name).join(", ")]);
  return (
    <dl className="grid grid-cols-[auto_1fr] gap-x-6 gap-y-2.5 text-sm">
      {rows.map(([k, v]) => (
        <div key={k} className="contents">
          <dt className="text-muted">{k}</dt>
          <dd>{v}</dd>
        </div>
      ))}
    </dl>
  );
}

async function Seasons({ data }: { data: TitleDetails }) {
  const numbers = (data.seasons ?? []).filter((s) => s.season_number > 0 && s.episode_count > 0).map((s) => s.season_number).slice(0, 15);
  const seasons = (await Promise.all(numbers.map((n) => getSeason(data.id, n).catch(() => null)))).filter(Boolean) as SeasonDetails[];
  if (!seasons.length) return null;
  return <SeasonTracker show={toSaved(data, "tv")} seasons={seasons} />;
}

async function TitleContent({ params }: { params: Props["params"] }) {
  const { type, data } = await load(params);
  const title = titleOf(data);
  const trailer = pickTrailer(data.videos?.results);
  const logo = data.images?.logos.find((l) => l.iso_639_1 === "en") ?? data.images?.logos[0];
  const runtime = type === "movie" ? runtimeLabel(data.runtime) : data.episode_run_time?.[0] ? `${data.episode_run_time[0]}m episodes` : null;
  const totalTV = type === "tv" && data.number_of_episodes ? data.number_of_episodes * (data.episode_run_time?.[0] ?? 45) : null;
  const cast = data.credits?.cast.slice(0, 20) ?? [];
  const recs = (data.recommendations?.results ?? []).filter((i) => i.poster_path);
  const similar = (data.similar?.results ?? []).filter((i) => i.poster_path);
  const providers = data["watch/providers"]?.results ?? {};

  const genreNames = data.genres?.map((g) => g.name) ?? [];
  const cert = certificate(data, type);
  const origin = type === "movie" ? data.production_countries?.[0]?.name : data.origin_country?.[0];
  const info: { icon: React.ReactNode; label: string; value: string | null | undefined }[] = [
    { icon: <Clock className="size-3.5" />, label: "Runtime", value: runtime },
    { icon: <Film className="size-3.5" />, label: "Genre", value: genreNames[0] },
    { icon: <ShieldCheck className="size-3.5" />, label: "Certificate", value: cert },
    { icon: <Briefcase className="size-3.5" />, label: "Budget", value: data.budget ? `$${data.budget.toLocaleString("en-US")}` : null },
    { icon: <DollarSign className="size-3.5" />, label: "Revenue", value: data.revenue ? `$${data.revenue.toLocaleString("en-US")}` : null },
    { icon: <Globe className="size-3.5" />, label: "Origin", value: origin },
  ];

  return (
    <article className="relative">
      <CloseButton />
      {/* Page tint taken from the poster, like the iOS sheet's dominant-colour background. */}
      <div className="pointer-events-none fixed inset-0 z-0 overflow-hidden bg-bg" aria-hidden>
        {(data.poster_path || data.backdrop_path) && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={img(data.poster_path ?? data.backdrop_path, "w185")!} alt="" className="h-full w-full scale-150 object-cover opacity-70 blur-[90px] saturate-150" />
        )}
        <div className="absolute inset-0 bg-black/45" />
      </div>

      <div className="relative z-10">
        <div className="relative aspect-[4/3] max-h-[62vh] w-full overflow-hidden sm:aspect-[16/9]">
          {data.backdrop_path && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={img(data.backdrop_path, "w1280")!} alt="" className="h-full w-full object-cover object-top [mask-image:linear-gradient(to_bottom,black_50%,transparent)]" fetchPriority="high" />
          )}
          {trailer && <HeaderTrailer videoKey={trailer.key} />}
        </div>

        <div className="rise relative -mt-16 px-4 text-white sm:-mt-24 sm:px-6">
          <span className="mb-4 inline-block rounded-md bg-tint px-2 py-0.5 text-[13px] font-bold tracking-wide text-white">{type === "tv" ? "SERIES" : "MOVIE"}</span>
          {logo ? (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={img(logo.file_path, "w500")!} alt={title} className="mb-5 max-h-24 max-w-[min(70%,380px)] object-contain transition-all duration-300 [html[data-trailer=playing]_&]:max-h-9 [html[data-trailer=playing]_&]:max-w-[160px] object-left drop-shadow-2xl" />
          ) : (
            <h1 className="mb-4 font-display text-4xl font-bold sm:text-5xl">{title}</h1>
          )}
          {logo && <h1 className="sr-only">{title}</h1>}
          <p className="flex flex-wrap items-center gap-x-4 text-[19px] text-white/75">
            <span>{yearOf(data)}</span>
            {type === "tv" && data.number_of_seasons ? <span>{data.number_of_seasons} Season{data.number_of_seasons === 1 ? "" : "s"}</span> : null}
            {runtime && <span>{runtime}</span>}
            {data.vote_average ? (
              <span className="inline-flex items-center gap-1.5"><Star className="size-5 fill-[#ffd60a] text-[#ffd60a]" />{data.vote_average.toFixed(1)}</span>
            ) : null}
          </p>
          {genreNames.length > 0 && <p className="mt-1.5 text-[15px] text-white/65">{genreNames.slice(0, 3).join(", ")}</p>}

          <div className="mt-8 max-w-3xl">
            <DetailActions item={data} type={type} />
          </div>

          {trailer && (
            <div className="mt-8 max-w-3xl">
              <PlayTrailer videoKey={trailer.key} title={title} />
            </div>
          )}

          <div className="rail mt-6 flex gap-2.5 overflow-x-auto">
            {data.vote_average ? (
              <div className="grid h-[76px] w-[68px] shrink-0 place-items-center rounded-2xl bg-black/30 py-2 backdrop-blur">
                <span className="text-[10px] leading-none font-black tracking-tight text-[#01b4e4]">TMDB</span>
                <span className="text-[19px] font-bold">{data.vote_average.toFixed(1)}</span>
              </div>
            ) : null}
            {data.vote_count ? (
              <div className="grid h-[76px] shrink-0 place-items-center rounded-2xl bg-black/30 px-4 py-2 backdrop-blur">
                <span className="text-[11px] font-semibold text-white/60">Votes</span>
                <span className="text-[19px] font-bold">{data.vote_count >= 1000 ? `${(data.vote_count / 1000).toFixed(1)}k` : data.vote_count}</span>
              </div>
            ) : null}
            <div className="grid h-[76px] shrink-0 place-items-center rounded-2xl bg-black/30 px-4 py-2 backdrop-blur">
              <span className="text-[11px] font-semibold text-white/60">Your rating</span>
              <StarRating k={keyOf(type, data.id)} />
            </div>
          </div>

          <dl className="rail mt-6 flex gap-6 overflow-x-auto pb-1">
            {info.filter((i) => i.value).map((i) => (
              <div key={i.label} className="shrink-0">
                <dt className="flex items-center gap-1.5 text-[13px] text-white/60">{i.icon}{i.label}</dt>
                <dd className="text-[17px] font-semibold">{i.value}</dd>
              </div>
            ))}
          </dl>

          {data.overview && (
            <section className="mt-8 max-w-3xl">
              <h2 className="mb-2 text-[22px] font-bold">About</h2>
              {data.tagline && <p className="mb-1 text-[17px] text-accent italic">{data.tagline}</p>}
              <p className="text-[17px] leading-relaxed text-white/80">{data.overview}</p>
            </section>
          )}
        </div>

        <div className="mt-10 space-y-8 px-4 sm:px-6">
          <WhereToWatch providers={providers} />
          {type === "tv" && (
            <Suspense fallback={<div className="skeleton h-64 rounded-card" />}>
              <Seasons data={data} />
            </Suspense>
          )}
          <div className="grid gap-4 md:grid-cols-2">
            <div className="rounded-[22px] bg-black/30 p-5 backdrop-blur">
              <h2 className="mb-4 text-[20px] font-bold">Details</h2>
              <Facts data={data} type={type} />
            </div>
            <div className="space-y-4">
              {totalTV ? (
                <div className="rounded-[22px] bg-black/30 p-5 backdrop-blur">
                  <h2 className="mb-1 text-[20px] font-bold">Time to finish</h2>
                  <p className="font-display text-3xl font-bold text-accent">{Math.round(totalTV / 60)} hrs</p>
                  <p className="mt-1 text-[15px] text-white/65">
                    {data.number_of_episodes} episodes. About {Math.max(1, Math.ceil(totalTV / 60 / 7))} week{Math.ceil(totalTV / 60 / 7) === 1 ? "" : "s"} at an hour a night.
                  </p>
                </div>
              ) : null}
              {data.belongs_to_collection && (
                <Link href={`/collection/${data.belongs_to_collection.id}`} className="press group relative block overflow-hidden rounded-[22px]">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  {data.belongs_to_collection.backdrop_path && <img src={img(data.belongs_to_collection.backdrop_path, "w780")!} alt="" className="aspect-video w-full object-cover" />}
                  <div className="absolute inset-0 bg-gradient-to-t from-black/90 to-transparent" />
                  <div className="absolute bottom-0 p-4">
                    <p className="text-[13px] font-semibold text-accent">Part of</p>
                    <p className="text-[19px] font-semibold text-white">{data.belongs_to_collection.name}</p>
                  </div>
                </Link>
              )}
              {data.imdb_id || data.external_ids?.imdb_id ? (
                <a href={`https://www.imdb.com/title/${data.imdb_id ?? data.external_ids?.imdb_id}/`} target="_blank" rel="noreferrer" className="block text-[15px] text-white/65 hover:text-white">
                  View on IMDb ↗
                </a>
              ) : null}
            </div>
          </div>
        </div>

      <div className="mt-12 space-y-10 pb-6">
        {cast.length > 0 && (
          <Rail title="Cast" gap="gap-5">
            {cast.map((c) => <PersonCard key={`${c.id}-${c.character}`} id={c.id} name={c.name} role={c.character} path={c.profile_path} />)}
          </Rail>
        )}
        {recs.length > 0 && (
          <Rail title="If you like this">
            {recs.map((i) => <PosterCard key={i.id} item={i} type={type} />)}
          </Rail>
        )}
        {similar.length > 0 && (
          <Rail title="Similar">
            {similar.map((i) => <PosterCard key={i.id} item={i} type={type} />)}
          </Rail>
        )}
      </div>
      </div>
    </article>
  );
}

export default function TitlePage({ params }: Props) {
  return (
    <Suspense
      fallback={
        <div>
          <div className="skeleton h-[560px]" />
          <div className="mt-8"><RailSkeleton /></div>
        </div>
      }
    >
      <TitleContent params={params} />
    </Suspense>
  );
}
