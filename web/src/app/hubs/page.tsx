import type { Metadata } from "next";
import Link from "next/link";
import { cacheLife } from "next/cache";
import { PageHeader } from "@/components/rail";
import { HUBS, type Hub } from "@/lib/catalog";
import { img } from "@/lib/media";
import { list } from "@/lib/tmdb";

export const metadata: Metadata = { title: "Hubs", description: "Studios and networks, all in one place." };

async function cover(h: Hub) {
  const items = h.networks
    ? await list("discover/tv", { with_networks: h.networks.join("|"), sort_by: "popularity.desc" })
    : await list("discover/movie", { with_companies: h.companies!.join("|"), sort_by: "popularity.desc" });
  return items.find((i) => i.backdrop_path)?.backdrop_path ?? null;
}

export default async function HubsPage() {
  "use cache";
  cacheLife("days");
  const covers = await Promise.all(HUBS.map(cover));
  const studios = HUBS.map((h, i) => ({ h, cover: covers[i] }));

  const grid = (items: typeof studios) => (
    <div className="grid grid-cols-1 gap-4 px-4 sm:grid-cols-2 sm:px-8 lg:grid-cols-3 xl:grid-cols-4">
      {items.map(({ h, cover }) => (
        <Link key={h.slug} href={`/hubs/${h.slug}`} className="frame group relative block aspect-[16/9] overflow-hidden rounded-card bg-surface">
          {cover && (
            // eslint-disable-next-line @next/next/no-img-element
            <img src={img(cover, "w780")!} alt="" loading="lazy" className="absolute inset-0 h-full w-full object-cover opacity-70 transition duration-500 group-hover:scale-105 group-hover:opacity-90" />
          )}
          <div className="absolute inset-0" style={{ background: `linear-gradient(to top, rgba(0,0,0,.92), rgba(0,0,0,.2)), radial-gradient(100% 100% at 0% 100%, ${h.color}55, transparent 60%)` }} />
          <div className="absolute bottom-0 p-4">
            <p className="font-display text-2xl font-bold tracking-tight text-white">{h.name}</p>
            <p className="text-sm text-white/70">{h.tagline}</p>
          </div>
        </Link>
      ))}
    </div>
  );

  return (
    <div className="space-y-10 pb-10">
      <PageHeader title="Hubs" subtitle="Every film from the studios you love, and every original from the networks." />
      <section>
        <h2 className="mb-3 px-4 font-display text-xl font-semibold sm:px-8">Studios</h2>
        {grid(studios.filter((s) => s.h.companies))}
      </section>
      <section>
        <h2 className="mb-3 px-4 font-display text-xl font-semibold sm:px-8">Networks & streamers</h2>
        {grid(studios.filter((s) => s.h.networks))}
      </section>
    </div>
  );
}
