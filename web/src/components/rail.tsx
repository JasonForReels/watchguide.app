"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useRef } from "react";
import { ChevronLeft, ChevronRight } from "lucide-react";

/** Section heading as iOS draws it: bold title, with a chevron when it opens a full list. */
export function SectionTitle({ title, subtitle, href, action }: { title: string; subtitle?: string; href?: string; action?: React.ReactNode }) {
  const heading = <h2 className="font-display text-[22px] leading-7 font-bold">{title}</h2>;
  return (
    <div className="mb-3 flex items-end justify-between gap-4 px-4 sm:px-8">
      <div className="min-w-0">
        {href ? (
          <Link href={href} className="inline-flex items-center gap-1 hover:opacity-80">
            {heading}
            <ChevronRight className="size-6 text-faint" strokeWidth={2.6} />
          </Link>
        ) : (
          heading
        )}
        {subtitle && <p className="mt-0.5 text-[15px] text-muted">{subtitle}</p>}
      </div>
      {action}
    </div>
  );
}

/** Glass circle back button, like a pushed view in a NavigationStack. */
export function BackButton({ fallback = "/more" }: { fallback?: string }) {
  const router = useRouter();
  return (
    <button
      type="button"
      aria-label="Back"
      onClick={() => (window.history.length > 1 ? router.back() : router.push(fallback))}
      className="glass press grid size-11 place-items-center rounded-full"
    >
      <ChevronLeft className="size-6" strokeWidth={2.4} />
    </button>
  );
}

/** Horizontal scroller with paging arrows on hover-capable screens. */
export function Rail({ title, subtitle, href, children, gap = "gap-4", action }: {
  title?: string;
  subtitle?: string;
  href?: string;
  children: React.ReactNode;
  gap?: string;
  action?: React.ReactNode;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const page = (dir: 1 | -1) => {
    const el = ref.current;
    if (el) el.scrollBy({ left: dir * el.clientWidth * 0.85, behavior: "smooth" });
  };

  return (
    <section className="group/rail relative">
      {title && <SectionTitle title={title} subtitle={subtitle} href={href} action={action} />}
      {/* A horizontal scroller clips vertically too, so leave room for the hover lift and outline. */}
      <div ref={ref} className={`rail -mt-3 -mb-3 flex overflow-x-auto px-4 pt-3 pb-5 sm:px-8 ${gap}`} style={{ scrollPaddingInline: "2rem" }}>
        {children}
      </div>
      <button
        type="button"
        onClick={() => page(-1)}
        aria-label="Scroll left"
        className="absolute top-1/2 left-2 hidden size-10 -translate-y-1/2 place-items-center rounded-full bg-black/60 text-white opacity-0 backdrop-blur transition group-hover/rail:opacity-100 hover:bg-black/80 [@media(hover:hover)]:grid"
      >
        <ChevronLeft className="size-5" />
      </button>
      <button
        type="button"
        onClick={() => page(1)}
        aria-label="Scroll right"
        className="absolute top-1/2 right-2 hidden size-10 -translate-y-1/2 place-items-center rounded-full bg-black/60 text-white opacity-0 backdrop-blur transition group-hover/rail:opacity-100 hover:bg-black/80 [@media(hover:hover)]:grid"
      >
        <ChevronRight className="size-5" />
      </button>
    </section>
  );
}

export function RailSkeleton({ title = true }: { title?: boolean }) {
  return (
    <section>
      {title && <div className="skeleton mx-4 mb-3 h-6 w-48 rounded sm:mx-8" />}
      <div className="flex gap-4 overflow-hidden px-4 sm:px-8">
        {Array.from({ length: 8 }, (_, i) => (
          <div key={i} className="w-36 shrink-0 sm:w-40">
            <div className="skeleton aspect-[2/3] rounded-card" />
            <div className="skeleton mt-2 h-3.5 w-3/4 rounded" />
          </div>
        ))}
      </div>
    </section>
  );
}

/**
 * Large-title header. Screens pushed from More get a back button; tab roots pass `root`.
 * On iPad the floating tab bar sits above, so the header leaves room for it.
 */
export function PageHeader({ title, subtitle, root = false, children }: { title: string; subtitle?: string; root?: boolean; children?: React.ReactNode }) {
  return (
    <header className={`px-4 pb-5 sm:px-8 ${root ? "pt-14 md:pt-24" : "pt-4 md:pt-3"}`}>
      {!root && (
        <div className="mb-3">
          <BackButton />
        </div>
      )}
      <div className={`flex flex-wrap items-end justify-between gap-4 ${root ? "" : "md:mt-10"}`}>
        <div>
          <h1 className="large-title">{title}</h1>
          {subtitle && <p className="mt-1 max-w-2xl text-[15px] text-muted">{subtitle}</p>}
        </div>
        {children}
      </div>
    </header>
  );
}
