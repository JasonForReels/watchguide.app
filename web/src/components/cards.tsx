"use client";

import Link from "next/link";
import { Bookmark, Check, Star } from "lucide-react";
import { hrefOf, img, keyOf, titleOf, typeOf, yearOf } from "@/lib/media";
import { useStore } from "@/lib/store";
import type { MediaItem, MediaType } from "@/lib/types";

export function Score({ value, className = "" }: { value?: number | null; className?: string }) {
  if (!value) return null;
  return (
    <span className={`inline-flex items-center gap-1 tabular-nums ${className}`}>
      <Star className="size-3 fill-accent text-accent" />
      {value.toFixed(1)}
    </span>
  );
}

/** Small corner badge showing whether a title is on the watchlist or watched. */
function StatusBadge({ k }: { k: string }) {
  const status = useStore((s) =>
    s.lists.watched.some((i) => i.key === k) ? "watched" : s.lists.want.some((i) => i.key === k) ? "want" : null,
  );
  if (!status) return null;
  return (
    <span
      className={`absolute top-2 right-2 grid size-6 place-items-center rounded-full shadow-lg ${
        status === "watched" ? "bg-accent text-on-accent" : "bg-black/70 text-accent backdrop-blur"
      }`}
      title={status === "watched" ? "Watched" : "On your watchlist"}
    >
      {status === "watched" ? <Check className="size-3.5" strokeWidth={3} /> : <Bookmark className="size-3 fill-current" />}
    </span>
  );
}

export function PosterArt({ path, alt, size = "w342", className = "" }: { path?: string | null; alt: string; size?: "w185" | "w342" | "w500"; className?: string }) {
  const src = img(path, size);
  return src ? (
    // eslint-disable-next-line @next/next/no-img-element
    <img src={src} alt={alt} loading="lazy" decoding="async" className={`h-full w-full object-cover ${className}`} />
  ) : (
    <div className={`grid h-full w-full place-items-center bg-surface p-3 text-center text-xs text-faint ${className}`}>{alt}</div>
  );
}

export function PosterCard({
  item,
  type,
  width = "w-36 sm:w-40",
  showMeta = true,
  caption,
}: {
  item: MediaItem;
  type?: MediaType;
  width?: string;
  showMeta?: boolean;
  caption?: string;
}) {
  const t = typeOf(item, type);
  const title = titleOf(item);
  return (
    <Link href={hrefOf(t, item.id)} className={`group block shrink-0 ${width}`}>
      <div className="frame relative aspect-[2/3] overflow-hidden rounded-[calc(var(--radius)+2px)] bg-surface after:pointer-events-none after:absolute after:inset-0 after:rounded-[inherit] after:ring-1 after:ring-text/10 after:ring-inset after:content-[''] transition-transform duration-300 group-hover:-translate-y-1 group-active:scale-[0.97]">
        <PosterArt path={item.poster_path} alt={title} />
        <StatusBadge k={keyOf(t, item.id)} />
      </div>
      {showMeta && (
        <div className="mt-2 px-0.5">
          <p className="truncate text-[13px] font-medium">{title}</p>
          <p className="flex items-center gap-2 text-[12px] text-muted">
            {caption ?? yearOf(item) ?? (t === "tv" ? "TV" : "Movie")}
            <Score value={item.vote_average} />
          </p>
        </div>
      )}
    </Link>
  );
}

/** Landscape card used by featured rows and spotlights. */
export function BackdropCard({ item, type, className = "w-72 sm:w-80", label }: { item: MediaItem; type?: MediaType; className?: string; label?: string }) {
  const t = typeOf(item, type);
  const title = titleOf(item);
  const src = img(item.backdrop_path, "w780");
  return (
    <Link href={hrefOf(t, item.id)} className={`group block shrink-0 ${className}`}>
      <div className="frame relative aspect-video overflow-hidden rounded-card bg-surface">
        {src && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={src} alt="" loading="lazy" className="h-full w-full object-cover transition-transform duration-500 group-hover:scale-[1.04]" />
        )}
        <div className="absolute inset-0 bg-gradient-to-t from-black/85 via-black/20 to-transparent" />
        <div className="absolute inset-x-0 bottom-0 p-3.5">
          {label && <p className="mb-0.5 text-[11px] font-semibold uppercase tracking-wider text-accent">{label}</p>}
          <p className="line-clamp-1 font-display text-base font-semibold text-white">{title}</p>
          <p className="text-xs text-white/70">
            {yearOf(item)} · {t === "tv" ? "Series" : "Film"}
          </p>
        </div>
        <StatusBadge k={keyOf(t, item.id)} />
      </div>
    </Link>
  );
}

export function PersonCard({ id, name, role, path }: { id: number; name: string; role?: string; path?: string | null }) {
  const src = img(path, "w185");
  return (
    <Link href={`/person/${id}`} className="group block w-24 shrink-0 text-center sm:w-28">
      <div className="mx-auto aspect-square w-full overflow-hidden rounded-full bg-surface ring-1 ring-line transition group-hover:ring-2 group-hover:ring-accent">
        {src ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={src} alt={name} loading="lazy" className="h-full w-full object-cover" />
        ) : (
          <div className="grid h-full place-items-center text-xl font-semibold text-faint">{name.slice(0, 1)}</div>
        )}
      </div>
      <p className="mt-2 line-clamp-1 text-[13px] font-medium">{name}</p>
      {role && <p className="line-clamp-1 text-xs text-muted">{role}</p>}
    </Link>
  );
}

export function PosterGrid({ items, type, empty }: { items: MediaItem[]; type?: MediaType; empty?: React.ReactNode }) {
  if (!items.length) return <>{empty ?? null}</>;
  return (
    <div className="grid grid-cols-[repeat(auto-fill,minmax(8.5rem,1fr))] gap-x-4 gap-y-6 sm:grid-cols-[repeat(auto-fill,minmax(10rem,1fr))]">
      {items.map((item) => (
        <PosterCard key={`${typeOf(item, type)}-${item.id}`} item={item} type={type} width="w-full" />
      ))}
    </div>
  );
}

export function PosterGridSkeleton({ count = 12 }: { count?: number }) {
  return (
    <div className="grid grid-cols-[repeat(auto-fill,minmax(8.5rem,1fr))] gap-x-4 gap-y-6 sm:grid-cols-[repeat(auto-fill,minmax(10rem,1fr))]">
      {Array.from({ length: count }, (_, i) => (
        <div key={i}>
          <div className="skeleton aspect-[2/3] rounded-card" />
          <div className="skeleton mt-2 h-3.5 w-3/4 rounded" />
        </div>
      ))}
    </div>
  );
}
