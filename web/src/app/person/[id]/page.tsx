import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { PosterCard } from "@/components/cards";
import { Bio } from "@/components/bio";
import { Rail, RailSkeleton } from "@/components/rail";
import { dedupe, formatDate, img, typeOf } from "@/lib/media";
import { getPerson } from "@/lib/tmdb";
import type { MediaItem } from "@/lib/types";

type Props = PageProps<"/person/[id]">;

async function load(params: Props["params"]) {
  const { id } = await params;
  if (!/^\d+$/.test(id)) notFound();
  try {
    return await getPerson(Number(id));
  } catch {
    notFound();
  }
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const p = await load(params);
  return { title: p.name, description: p.biography?.slice(0, 160) };
}

const byDateDesc = (a: MediaItem, b: MediaItem) =>
  (b.release_date || b.first_air_date || "0").localeCompare(a.release_date || a.first_air_date || "0");

async function PersonContent({ params }: { params: Props["params"] }) {
  const p = await load(params);
  const cast = p.combined_credits?.cast ?? [];
  const crew = p.combined_credits?.crew ?? [];
  const known = dedupe([...cast, ...crew].filter((i) => i.poster_path && (i.vote_count ?? 0) > 50))
    .sort((a, b) => (b.vote_count ?? 0) - (a.vote_count ?? 0))
    .slice(0, 20);
  const films = dedupe(cast.filter((i) => typeOf(i) === "movie" && i.poster_path)).sort(byDateDesc);
  const shows = dedupe(cast.filter((i) => typeOf(i) === "tv" && i.poster_path && !/(Self|Himself|Herself)/.test((i as { character?: string }).character ?? ""))).sort(byDateDesc);
  const directed = dedupe(crew.filter((i) => (i as { job?: string }).job === "Director" && i.poster_path)).sort(byDateDesc);
  const age = p.birthday && p.deathday ? Math.floor((new Date(p.deathday).getTime() - new Date(p.birthday).getTime()) / 3.15576e10) : null;

  return (
    <div className="space-y-10 pb-6">
      <header className="flex flex-col gap-6 px-4 pt-10 sm:flex-row sm:px-8">
        <div className="frame aspect-[2/3] w-40 shrink-0 overflow-hidden rounded-card bg-surface sm:w-52">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          {p.profile_path && <img src={img(p.profile_path, "w500")!} alt={p.name} className="h-full w-full object-cover" />}
        </div>
        <div className="rise max-w-3xl">
          <div className="marquee-bulbs mb-4 w-24" aria-hidden="true" />
          <h1 className="font-display text-4xl font-bold tracking-tight">{p.name}</h1>
          <p className="mt-2 text-sm text-muted">
            {[p.known_for_department, p.birthday && `Born ${formatDate(p.birthday)}`, p.deathday && `Died ${formatDate(p.deathday)} (${age})`, p.place_of_birth]
              .filter(Boolean)
              .join(" · ")}
          </p>
          {p.biography && <Bio text={p.biography} />}
        </div>
      </header>
      {known.length > 0 && <Rail title="Known for">{known.map((i) => <PosterCard key={`${typeOf(i)}-${i.id}`} item={i} />)}</Rail>}
      {directed.length > 0 && <Rail title="Directed">{directed.map((i) => <PosterCard key={i.id} item={i} />)}</Rail>}
      {films.length > 0 && <Rail title="Films">{films.map((i) => <PosterCard key={i.id} item={i} type="movie" />)}</Rail>}
      {shows.length > 0 && <Rail title="TV">{shows.map((i) => <PosterCard key={i.id} item={i} type="tv" />)}</Rail>}
    </div>
  );
}

export default function PersonPage({ params }: Props) {
  return (
    <Suspense fallback={<div className="space-y-8 pt-10"><div className="skeleton mx-8 h-72 w-52 rounded-card" /><RailSkeleton /></div>}>
      <PersonContent params={params} />
    </Suspense>
  );
}
