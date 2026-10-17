import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { Suspense } from "react";
import { CollectionProgress } from "@/components/collection-progress";
import { formatDate, img, toSaved } from "@/lib/media";
import { getCollection } from "@/lib/tmdb";

type Props = PageProps<"/collection/[id]">;

async function load(params: Props["params"]) {
  const { id } = await params;
  if (!/^\d+$/.test(id)) notFound();
  try {
    return await getCollection(Number(id));
  } catch {
    notFound();
  }
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const c = await load(params);
  return { title: c.name, description: c.overview };
}

async function CollectionContent({ params }: { params: Props["params"] }) {
  const c = await load(params);
  const parts = [...c.parts].sort((a, b) => (a.release_date || "9999").localeCompare(b.release_date || "9999"));
  return (
    <div>
      <div className="relative h-[42vh] min-h-[300px] overflow-hidden">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        {c.backdrop_path && <img src={img(c.backdrop_path, "w1280")!} alt="" className="absolute inset-0 h-full w-full object-cover" />}
        <div className="absolute inset-0 bg-gradient-to-t from-bg via-bg/50 to-transparent" />
        <div className="absolute bottom-0 px-4 pb-8 sm:px-8">
          <p className="text-xs font-semibold uppercase tracking-[0.18em] text-accent">Franchise timeline</p>
          <h1 className="mt-1 font-display text-4xl font-bold tracking-tight">{c.name}</h1>
          <p className="mt-2 max-w-2xl text-[15px] text-text/85">{c.overview}</p>
        </div>
      </div>
      <div className="px-4 sm:px-8">
        <CollectionProgress items={parts.map((p) => toSaved(p, "movie"))} />
        <ol className="relative mt-6 space-y-4 border-l-2 border-line pl-6">
          {parts.map((p, i) => (
            <li key={p.id} className="relative">
              <span className="absolute top-6 -left-[33px] grid size-4 place-items-center rounded-full border-2 border-accent bg-bg" />
              <Link href={`/title/movie/${p.id}`} className="group flex gap-4 rounded-card bg-surface p-3 transition hover:bg-raised">
                <div className="frame aspect-[2/3] w-20 shrink-0 overflow-hidden rounded-[calc(var(--radius)*0.6)] bg-bg">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  {p.poster_path && <img src={img(p.poster_path, "w185")!} alt="" className="h-full w-full object-cover" />}
                </div>
                <div className="min-w-0 py-1">
                  <p className="text-xs font-semibold text-accent">Part {i + 1} · {formatDate(p.release_date)}</p>
                  <p className="font-display text-lg font-semibold group-hover:text-accent">{p.title}</p>
                  <p className="mt-1 line-clamp-2 text-sm text-muted">{p.overview}</p>
                </div>
              </Link>
            </li>
          ))}
        </ol>
      </div>
    </div>
  );
}

export default function CollectionPage({ params }: Props) {
  return (
    <Suspense fallback={<div className="skeleton h-[42vh]" />}>
      <CollectionContent params={params} />
    </Suspense>
  );
}
