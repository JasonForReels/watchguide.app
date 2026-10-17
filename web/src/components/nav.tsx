"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useCallback, useEffect, useLayoutEffect, useRef, useState } from "react";
import { CircleEllipsis, Flame, Popcorn, Search, Settings, SlidersHorizontal, Tv } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { ensureLensBackdropFilter, ensureLensFilter, lensBackdropId, lensFilterId, supported } from "./liquid-glass";

interface Item {
  href: string;
  label: string;
  icon: LucideIcon;
}

/** Same tabs, same order as the iOS tab bar (ContentView.swift). */
const TABS: Item[] = [
  { href: "/", label: "Browse", icon: Popcorn },
  { href: "/streamq", label: "StreamQ", icon: Tv },
  { href: "/pops", label: "Pops", icon: Flame },
  { href: "/more", label: "More", icon: CircleEllipsis },
  { href: "/search", label: "Search", icon: Search },
];

/** Screens reached from the More hub, so More stays selected while they're open. */
const MORE_ROUTES = ["/more", "/lists", "/tonight", "/discover", "/calendar", "/hubs", "/atlas", "/stats", "/settings"];

function isActive(path: string | null, href: string) {
  if (path === null) return false;
  if (href === "/more") return MORE_ROUTES.some((r) => path === r || path.startsWith(`${r}/`));
  return href === "/" ? path === "/" : path === href || path.startsWith(`${href}/`);
}

/** Nav with the current route highlighted. Reads the URL, so render it inside <Suspense>. */
export function ActiveNav() {
  return <Nav path={usePathname()} />;
}

/** Plain nav markup. With no `path` nothing is highlighted, which suits the prerendered shell. */
export function Nav({ path = null }: { path?: string | null }) {
  // The title page and Tonight are presented full-screen on iOS, with their own close buttons.
  const immersive = (path?.startsWith("/title/") || path === "/tonight") ?? false;
  const active = TABS.findIndex((t) => isActive(path, t.href));

  return (
    <>
      {/* Scroll-edge fades behind the floating bars. */}
      {!immersive && (
        <>
          <div aria-hidden className="scroll-edge-top pointer-events-none fixed inset-x-0 top-0 z-30 hidden h-24 md:block" />
          <div aria-hidden className="scroll-edge-bottom pointer-events-none fixed inset-x-0 bottom-0 z-30 h-32 md:hidden" />
        </>
      )}

      {/* iPad and desktop: floating capsule at the top, like iPadOS 26 tab bars. */}
      <div className={`pointer-events-none fixed inset-x-0 top-0 z-40 hidden items-center justify-center pt-3 md:flex ${immersive ? "md:hidden" : ""}`}>
        <TabBar active={active} variant="top" />
        <div suppressHydrationWarning className="glass-bar pointer-events-auto absolute right-4 flex items-center rounded-full p-1">
          <Link href="/discover" aria-label="Moods and filters" className="press grid size-9 place-items-center rounded-full hover:bg-text/5">
            <SlidersHorizontal className="size-[18px]" strokeWidth={2.2} />
          </Link>
          <Link href="/settings" aria-label="Settings" className="press grid size-9 place-items-center rounded-full hover:bg-text/5">
            <Settings className="size-[19px]" strokeWidth={2.2} />
          </Link>
        </div>
      </div>

      {/* iPhone: floating Liquid Glass tab bar. */}
      <div className={`fixed inset-x-0 bottom-0 z-40 px-4 pb-[max(env(safe-area-inset-bottom),12px)] md:hidden ${immersive ? "hidden" : ""}`}>
        <TabBar active={active} variant="bottom" />
      </div>
    </>
  );
}

/** Movement (px) before a press on the bar becomes a drag instead of a tap. */
const DRAG_SLOP = 6;
/** iOS-like spring: a quick settle with a little overshoot. */
const SPRING = "cubic-bezier(0.34, 1.45, 0.64, 1)";

/**
 * Tab bar with the iOS 26 drag gesture: press anywhere on the bar and slide, a glass lens follows
 * your finger and magnifies the tab under it, and letting go selects that tab. Taps work as links.
 */
function TabBar({ active, variant }: { active: number; variant: "top" | "bottom" }) {
  const router = useRouter();
  const bar = useRef<HTMLElement>(null);
  const items = useRef<(HTMLAnchorElement | null)[]>([]);
  const press = useRef<{ id: number; x: number; dragging: boolean } | null>(null);
  const [rects, setRects] = useState<{ left: number; width: number }[]>([]);
  const [barWidth, setBarWidth] = useState(0);
  const [barHeight, setBarHeight] = useState(0);
  const justDragged = useRef(false);
  const [lensX, setLensX] = useState<number | null>(null);
  // Picked by a drag but the route hasn't changed yet; keeps the pill where the finger left it.
  // Stored with the tab that was active when it was picked, so it lapses once the route changes.
  const [picked, setPicked] = useState<{ index: number; from: number } | null>(null);
  const pending = picked && picked.from === active ? picked.index : null;
  const setPending = (index: number) => setPicked({ index, from: active });
  const [mounted, setMounted] = useState(false);
  // Chromium can refract the real backdrop, so the lens shows the page behind the bar too.
  // Elsewhere it falls back to a magnified copy of the tab row.
  const [seeThrough] = useState(() => typeof navigator !== "undefined" && supported());

  const measure = useCallback(() => {
    const b = bar.current?.getBoundingClientRect();
    if (!b) return;
    // Layout size, not the scaled-on-drag box.
    setBarWidth(bar.current!.clientWidth);
    setBarHeight(bar.current!.clientHeight);
    setRects(items.current.map((el) => {
      const r = el?.getBoundingClientRect();
      return r ? { left: r.left - b.left, width: r.width } : { left: 0, width: 0 };
    }));
  }, []);

  useLayoutEffect(() => {
    measure();
    const ro = new ResizeObserver(measure);
    if (bar.current) ro.observe(bar.current);
    // Let the first placement happen without animating in from the left edge.
    const t = requestAnimationFrame(() => setMounted(true));
    return () => { ro.disconnect(); cancelAnimationFrame(t); };
  }, [measure]);

  const indexAt = (x: number) => {
    let best = 0;
    let dist = Infinity;
    rects.forEach((r, i) => {
      const d = Math.abs(r.left + r.width / 2 - x);
      if (d < dist) { dist = d; best = i; }
    });
    return best;
  };

  const localX = (clientX: number) => clientX - (bar.current?.getBoundingClientRect().left ?? 0);

  const hovered = lensX === null ? null : indexAt(lensX);
  const selected = hovered ?? pending ?? active;
  const lastHover = useRef<number | null>(null);
  useEffect(() => {
    // A light tick as the lens crosses into a new tab, where the device supports it (Android).
    if (hovered !== null && lastHover.current !== null && hovered !== lastHover.current) navigator.vibrate?.(6);
    lastHover.current = hovered;
  }, [hovered]);

  const onPointerDown = (e: React.PointerEvent) => {
    if (e.button !== 0) return;
    press.current = { id: e.pointerId, x: e.clientX, dragging: false };
    // iOS 26 swells the lens as soon as a tab is touched, not only once you drag.
    setLensX(localX(e.clientX));
  };

  const onPointerMove = (e: React.PointerEvent) => {
    const p = press.current;
    if (!p || p.id !== e.pointerId) return;
    if (!p.dragging) {
      if (Math.abs(e.clientX - p.x) < DRAG_SLOP) return;
      p.dragging = true;
      // Capture only once it's a drag, so plain taps still land on the links.
      try { bar.current?.setPointerCapture(e.pointerId); } catch {}
    }
    setLensX(localX(e.clientX));
  };

  const finish = (e: React.PointerEvent, commit: boolean) => {
    const p = press.current;
    press.current = null;
    if (!p?.dragging) {
      // A tap: let the lens settle back and the link handle navigation.
      setLensX(null);
      return;
    }
    const i = indexAt(localX(e.clientX));
    setLensX(null);
    // The click that follows a drag must not also follow a link.
    justDragged.current = true;
    setTimeout(() => { justDragged.current = false; }, 0);
    if (!commit) return;
    setPending(i);
    if (i !== active) router.push(TABS[i].href);
  };

  // Pill geometry: follows the finger while dragging, otherwise springs to the selected tab.
  const target = rects[selected];
  const width = target?.width ?? 0;
  const left = lensX !== null ? Math.min(Math.max(lensX - width / 2, 4), barWidth - width - 4) : target?.left ?? 0;
  const dragging = lensX !== null;
  const showPill = selected >= 0 && !!target;

  const top = variant === "top";

  // The lens rises a little above and below the bar, like the iOS droplet.
  const LENS_OVERHANG = 6;
  const lensH = barHeight + LENS_OVERHANG * 2;
  const lensFilter = lensFilterId(width, lensH);
  const lensBackdrop = lensBackdropId(width, lensH);
  useLayoutEffect(() => {
    if (!dragging) return;
    if (seeThrough) ensureLensBackdropFilter(width, lensH);
    else ensureLensFilter(width, lensH);
  }, [dragging, width, lensH, seeThrough]);

  const content = (i: number, on: boolean) => {
    const { href, label, icon: Icon } = TABS[i];
    if (top) return href === "/search" ? <Icon className="size-[18px]" strokeWidth={2.2} /> : label;
    return (
      <>
        <Icon className={`size-6 ${on && href !== "/search" ? "fill-current/25" : ""}`} strokeWidth={on ? 2.3 : 1.9} />
        {label}
      </>
    );
  };
  const itemClass = (i: number, on: boolean) =>
    top
      ? `rounded-full py-1.5 text-[15px] font-medium ${TABS[i].href === "/search" ? "px-3" : "px-4"} ${on ? "text-tint" : "text-text"}`
      : `flex flex-1 flex-col items-center gap-0.5 rounded-full pt-2 pb-1.5 text-[10px] font-semibold ${on ? "text-tint" : "text-text"}`;
  const rowClass = `flex items-center p-1 ${top ? "gap-0.5" : ""}`;

  const lensFrame = {
    left,
    width,
    top: -LENS_OVERHANG,
    height: lensH,
    transform: "scale(1.1)",
    transition: `left 0.08s linear, width 0.3s ${SPRING}`,
    boxShadow: "0 10px 28px rgb(0 0 0 / 0.38), inset 0 1.5px 0 rgb(255 255 255 / 0.5), inset 0 -1px 0 rgb(255 255 255 / 0.18), inset 0 0 0 0.5px rgb(255 255 255 / 0.35)",
  } as const;
  const sheen = <span className="absolute inset-x-[22%] top-[3%] h-[16%] rounded-full bg-gradient-to-b from-white/14 to-transparent blur-[1px]" />;

  return (
    <div className={`pointer-events-auto relative ${top ? "" : "mx-auto max-w-md"}`}>
    <nav
      suppressHydrationWarning
      ref={bar}
      aria-label="Main"
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={(e) => finish(e, true)}
      onPointerCancel={(e) => finish(e, false)}
      onClickCapture={(e) => { if (justDragged.current) { e.preventDefault(); e.stopPropagation(); } }}
      className={`glass-bar relative touch-none rounded-full select-none ${rowClass}`}
      style={{ transform: dragging ? "scale(1.03)" : "scale(1)", transition: `transform 0.35s ${SPRING}` }}
    >
      {showPill && !dragging && (
        <span
          aria-hidden
          className="pointer-events-none absolute top-1 bottom-1 rounded-full bg-text/10"
          style={{
            left,
            width,
            transition: mounted ? `left 0.45s ${SPRING}, width 0.3s ${SPRING}` : "none",
          }}
        />
      )}
      {TABS.map(({ href, label }, i) => (
        <Link
          key={href}
          ref={(el) => { items.current[i] = el; }}
          href={href}
          draggable={false}
          onClick={() => setPending(i)}
          aria-current={i === active ? "page" : undefined}
          aria-label={top && href === "/search" ? label : undefined}
          className={`relative z-10 transition-colors ${itemClass(i, i === selected)}`}
        >
          {content(i, i === selected)}
        </Link>
      ))}

      {/*
        Fallback lens (no SVG backdrop filters): it can't see through the bar's glass, so it
        carries its own copy of the tab row, lined up with the real one, scaled up around the lens
        centre and bent at the rim by an SVG displacement filter.
      */}
      {dragging && showPill && !seeThrough && (
        <span
          aria-hidden
          className="pointer-events-none absolute z-20 overflow-hidden rounded-full"
          style={{ ...lensFrame, background: "color-mix(in oklab, var(--surface), var(--text) 9%)" }}
        >
          <span className="absolute inset-0" style={{ filter: `url(#${lensFilter})` }}>
            <span
              className={`absolute ${rowClass}`}
              style={{
                left: -left,
                top: LENS_OVERHANG,
                width: barWidth,
                height: barHeight,
                transform: "scale(1.16)",
                transformOrigin: `${left + width / 2}px ${barHeight / 2}px`,
              }}
            >
              {TABS.map(({ href }, i) => (
                <span key={href} className={itemClass(i, i === hovered)}>{content(i, i === hovered)}</span>
              ))}
            </span>
          </span>
          {sheen}
        </span>
      )}
    </nav>

    {/*
      See-through lens: a sibling of the bar rather than a child, so its backdrop is everything
      under it (the page behind the bar, the bar's glass and the tab icons), which it magnifies
      and bends at the rim like a droplet of glass.
    */}
    {dragging && showPill && seeThrough && (
      <span
        aria-hidden
        className="pointer-events-none absolute z-20 overflow-hidden rounded-full"
        style={{ ...lensFrame, backdropFilter: `url(#${lensBackdrop})` }}
      >
        {sheen}
      </span>
    )}
    </div>
  );
}
