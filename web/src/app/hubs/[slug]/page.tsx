import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { BackdropCard, PosterCard } from "@/components/cards";
import { Rail } from "@/components/rail";
import { HUBS, hubBySlug } from "@/lib/catalog";
import { img } from "@/lib/media";
import { list } from "@/lib/tmdb";

type Props = PageProps<"/hubs/[slug]">;

export function generateStaticParams() {
  return HUBS.map((h) => ({ slug: h.slug }));
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const hub = hubBySlug((await params).slug);
  return { title: hub?.name ?? "Hub" };
}

export const revalidate = 3600;

async function HubContent({ slug }: { slug: string }) {
  const hub = hubBySlug(slug);
  if (!hub) notFound();

  const movie = hub.companies ? { with_companies: hub.companies.join("|") } : null;
  const tv = hub.networks
    ? { with_networks: hub.networks.join("|") }
    : hub.tvCompanies
      ? { with_companies: hub.tvCompanies.join("|") }
      : null;

  const [popular, newest, best, tvPopular, tvBest] = await Promise.all([
    movie ? list("discover/movie", { ...movie, sort_by: "popularity.desc" }) : [],
    movie ? list("discover/movie", { ...movie, sort_by: "primary_release_date.desc", "vote_count.gte": 20 }) : [],
    movie ? list("discover/movie", { ...movie, sort_by: "vote_average.desc", "vote_count.gte": 400 }) : [],
    tv ? list("discover/tv", { ...tv, sort_by: "popularity.desc" }) : [],
    tv ? list("discover/tv", { ...tv, sort_by: "vote_average.desc", "vote_count.gte": 200 }) : [],
  ]);
  const hero = [...popular, ...tvPopular].find((i) => i.backdrop_path);

  return (
    <div className="space-y-10 pb-10">
      <header className="relative h-[46vh] min-h-[320px] overflow-hidden">
        {hero && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={img(hero.backdrop_path, "w1280")!} alt="" className="absolute inset-0 h-full w-full object-cover" />
        )}
        <div className="absolute inset-0" style={{ background: `linear-gradient(to top, var(--bg), transparent 70%), radial-gradient(120% 100% at 0% 100%, ${hub.color}66, transparent 60%)` }} />
        <div className="absolute bottom-0 px-4 pb-8 sm:px-8">
          <div className="marquee-bulbs mb-4 w-24" aria-hidden="true" />
          <h1 className="font-display text-5xl font-black tracking-tight sm:text-6xl">{hub.name}</h1>
          <p className="mt-1 text-lg text-text/80">{hub.tagline}</p>
        </div>
      </header>
      {popular.length > 0 && <Rail title="Most popular">{popular.map((i) => <PosterCard key={i.id} item={i} type="movie" />)}</Rail>}
      {newest.length > 0 && (
        <Rail title="Latest & upcoming">
          {newest.filter((i) => i.backdrop_path).map((i) => <BackdropCard key={i.id} item={i} type="movie" />)}
        </Rail>
      )}
      {best.length > 0 && <Rail title="Best rated">{best.map((i) => <PosterCard key={i.id} item={i} type="movie" />)}</Rail>}
      {tvPopular.length > 0 && <Rail title={hub.networks ? "Popular originals" : "Series"}>{tvPopular.map((i) => <PosterCard key={i.id} item={i} type="tv" />)}</Rail>}
      {tvBest.length > 0 && <Rail title="Best rated series">{tvBest.map((i) => <PosterCard key={i.id} item={i} type="tv" />)}</Rail>}
    </div>
  );
}

export default async function HubPage({ params }: Props) {
  const { slug } = await params;
  return <HubContent slug={slug} />;
}
