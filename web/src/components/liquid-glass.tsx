"use client";

import { useEffect } from "react";

/**
 * Liquid Glass material for every `.glass` / `.glass-clear` surface.
 *
 * iOS 26 glass doesn't just blur what's behind it: the rim acts like a lens, bending the
 * background inward, with a slight colour fringe and a lift in saturation. The web can do that
 * with an SVG displacement filter used as a `backdrop-filter`, which only Chromium renders
 * (Chrome on Android, desktop Chrome and Edge). Everywhere else the frosted CSS fallback in
 * globals.css stays in place.
 *
 * Each surface gets a displacement map drawn for its exact size and corner radius, so capsules,
 * circles and cards all refract along their own edges. Maps are cached by shape.
 */

type Kind = "frosted" | "clear" | "bar";

const PARAMS: Record<Kind, { blur: number; scale: number; saturate: number; dim?: number }> = {
  // Tab bars: the clear material's refraction, but denser so icons stay legible over posters.
  bar: { blur: 2.2, scale: 64, saturate: 1.6, dim: 0.82 },
  // Bars and panels: legible first, so more blur and a gentler bend.
  frosted: { blur: 7, scale: 46, saturate: 1.7 },
  // Buttons over photography: clear, so the lensing reads.
  clear: { blur: 1.6, scale: 64, saturate: 1.5 },
};

const NS = "http://www.w3.org/2000/svg";
const SELECTOR = ".glass, .glass-clear, .glass-bar";

export function supported() {
  const ua = navigator.userAgent;
  // iOS browsers are all WebKit (CriOS etc.), which can't apply SVG backdrop filters.
  return /Chrome\/|Chromium\/|Edg\//.test(ua) && !/CriOS|FxiOS|EdgiOS/.test(ua);
}

/**
 * Displacement map for a rounded rectangle. Red/green hold the x/y offset (128 = none).
 * Inside a rim band the background is sampled from further inward, strongest at the very edge,
 * which is how a thick convex glass edge refracts.
 */
function drawMap(w: number, h: number, r: number, rim?: number): string {
  const c = document.createElement("canvas");
  c.width = w;
  c.height = h;
  const ctx = c.getContext("2d")!;
  const data = ctx.createImageData(w, h);
  const hw = w / 2;
  const hh = h / 2;
  const bezel = rim ?? Math.max(6, Math.min(r * 0.9, 22, hh));

  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const px = x + 0.5 - hw;
      const py = y + 0.5 - hh;
      const qx = Math.abs(px) - (hw - r);
      const qy = Math.abs(py) - (hh - r);
      // Signed distance to the rounded-rect edge, and the outward normal.
      let sdf: number;
      let nx: number;
      let ny: number;
      if (qx > 0 && qy > 0) {
        const len = Math.hypot(qx, qy);
        sdf = len - r;
        nx = (qx / len) * Math.sign(px);
        ny = (qy / len) * Math.sign(py);
      } else {
        sdf = Math.max(qx, qy) - r;
        if (qx > qy) { nx = Math.sign(px); ny = 0; } else { nx = 0; ny = Math.sign(py); }
      }

      let dx = 0;
      let dy = 0;
      const d = -sdf;
      if (d >= 0 && d < bezel) {
        const t = 1 - d / bezel;
        const mag = t * t * (3 - 2 * t) * t; // eased: flat in the middle, steep at the rim
        dx = -nx * mag;
        dy = -ny * mag;
      }
      const i = (y * w + x) * 4;
      data.data[i] = 128 + dx * 127;
      data.data[i + 1] = 128 + dy * 127;
      data.data[i + 2] = 128;
      data.data[i + 3] = 255;
    }
  }
  ctx.putImageData(data, 0, 0);
  return c.toDataURL();
}

function el<K extends keyof SVGElementTagNameMap>(name: K, attrs: Record<string, string | number>, ...children: SVGElement[]) {
  const node = document.createElementNS(NS, name);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, String(v));
  children.forEach((ch) => node.appendChild(ch));
  return node;
}

/** One channel of the colour fringe: displace by `scale`, keep only that channel. */
function channel(scale: number, keep: 0 | 1 | 2, result: string) {
  const m = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0];
  m[keep * 6] = 1;
  return [
    el("feDisplacementMap", { in: "blurred", in2: "map", scale, xChannelSelector: "R", yChannelSelector: "G", result: `${result}-d` }),
    el("feColorMatrix", { in: `${result}-d`, type: "matrix", values: m.join(" "), result }),
  ];
}

function buildFilter(id: string, w: number, h: number, r: number, kind: Kind) {
  const p = PARAMS[kind];
  return el(
    "filter",
    { id, x: 0, y: 0, width: w, height: h, filterUnits: "userSpaceOnUse", primitiveUnits: "userSpaceOnUse", "color-interpolation-filters": "sRGB" },
    el("feGaussianBlur", { in: "SourceGraphic", stdDeviation: p.blur, result: "blurred" }),
    el("feImage", { href: drawMap(w, h, r), x: 0, y: 0, width: w, height: h, preserveAspectRatio: "none", result: "map" }),
    // Red bends a little more than green, green more than blue: a faint prismatic rim.
    ...channel(p.scale, 0, "r"),
    ...channel(p.scale * 0.94, 1, "g"),
    ...channel(p.scale * 0.88, 2, "b"),
    el("feBlend", { in: "r", in2: "g", mode: "screen", result: "rg" }),
    el("feBlend", { in: "rg", in2: "b", mode: "screen", result: "rgb" }),
    el("feColorMatrix", { in: "rgb", type: "saturate", values: p.saturate, result: "sat" }),
    ...(p.dim
      ? [el("feComponentTransfer", { in: "sat" },
          el("feFuncR", { type: "linear", slope: p.dim }),
          el("feFuncG", { type: "linear", slope: p.dim }),
          el("feFuncB", { type: "linear", slope: p.dim }))]
      : []),
  );
}

/** Shared <defs> for filters used through CSS `filter` (works in every engine, unlike backdrop). */
function sharedDefs(): Element {
  let defs: Element | null = document.getElementById("lg-shared-defs");
  if (!defs) {
    const svg = el("svg", { width: 0, height: 0, "aria-hidden": "true", style: "position:absolute;width:0;height:0;overflow:hidden" });
    defs = el("defs", { id: "lg-shared-defs" });
    svg.appendChild(defs);
    document.body.appendChild(svg);
  }
  return defs;
}

/** Id of the lens filter for a w×h capsule. Pure, so it can be computed during render. */
export const lensFilterId = (w: number, h: number) => `lg-lens-${Math.round(w)}x${Math.round(h)}`;

/**
 * Creates (once) the refraction filter for the tab-bar lens: the rim bends its content like
 * the edge of a glass droplet, with the same faint colour fringe as the surfaces.
 */
export function ensureLensFilter(w: number, h: number) {
  w = Math.round(w);
  h = Math.round(h);
  const id = lensFilterId(w, h);
  if (w < 8 || h < 8 || document.getElementById(id)) return;
  const map = el("feImage", { href: drawMap(w, h, h / 2, Math.min(9, h / 5)), x: 0, y: 0, width: w, height: h, preserveAspectRatio: "none", result: "map" });
  const ch = (scale: number, keep: 0 | 1 | 2, result: string) => {
    const m = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0];
    m[keep * 6] = 1;
    return [
      el("feDisplacementMap", { in: "SourceGraphic", in2: "map", scale, xChannelSelector: "R", yChannelSelector: "G", result: `${result}-d` }),
      el("feColorMatrix", { in: `${result}-d`, type: "matrix", values: m.join(" "), result }),
    ];
  };
  sharedDefs().appendChild(
    el(
      "filter",
      { id, x: 0, y: 0, width: w, height: h, filterUnits: "userSpaceOnUse", primitiveUnits: "userSpaceOnUse", "color-interpolation-filters": "sRGB" },
      map,
      // A narrow, gentle rim: enough to bend what passes under the edge without smearing labels.
      ...ch(18, 0, "r"),
      ...ch(16.5, 1, "g"),
      ...ch(15, 2, "b"),
      el("feComposite", { in: "r", in2: "g", operator: "arithmetic", k1: 0, k2: 1, k3: 1, k4: 0, result: "rg" }),
      el("feComposite", { in: "rg", in2: "b", operator: "arithmetic", k1: 0, k2: 1, k3: 1, k4: 0 }),
    ),
  );
}

/**
 * Map for a magnifying droplet: every point samples from closer to the centre (zoom), and the
 * rim band bends further inward on top of that. Offsets are in pixels, so the matching
 * feDisplacementMap scale is returned alongside.
 */
function drawLensMap(w: number, h: number, zoom: number, rim: number, rimPx: number) {
  const r = h / 2;
  const hw = w / 2;
  const hh = h / 2;
  const k = 1 - 1 / zoom;
  const maxDisp = Math.hypot(hw, hh) * k + rimPx + 1;
  const scale = maxDisp * 2;
  const c = document.createElement("canvas");
  c.width = w;
  c.height = h;
  const ctx = c.getContext("2d")!;
  const img = ctx.createImageData(w, h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const px = x + 0.5 - hw;
      const py = y + 0.5 - hh;
      // Zoom: sample from p * (1/zoom), i.e. offset -p * k.
      let dx = -px * k;
      let dy = -py * k;
      const qx = Math.abs(px) - (hw - r);
      const qy = Math.abs(py) - (hh - r);
      let sdf: number;
      let nx: number;
      let ny: number;
      if (qx > 0 && qy > 0) {
        const len = Math.hypot(qx, qy);
        sdf = len - r;
        nx = (qx / len) * Math.sign(px);
        ny = (qy / len) * Math.sign(py);
      } else {
        sdf = Math.max(qx, qy) - r;
        if (qx > qy) { nx = Math.sign(px); ny = 0; } else { nx = 0; ny = Math.sign(py); }
      }
      const d = -sdf;
      if (d >= 0 && d < rim) {
        const t = 1 - d / rim;
        const mag = t * t * (3 - 2 * t) * t * rimPx;
        dx -= nx * mag;
        dy -= ny * mag;
      }
      const i = (y * w + x) * 4;
      img.data[i] = 128 + (dx / maxDisp) * 127;
      img.data[i + 1] = 128 + (dy / maxDisp) * 127;
      img.data[i + 2] = 128;
      img.data[i + 3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  return { url: c.toDataURL(), scale };
}

/** Id of the see-through lens filter for a w×h droplet. Pure, for use during render. */
export const lensBackdropId = (w: number, h: number) => `lg-lensbd-${Math.round(w)}x${Math.round(h)}`;

/**
 * Backdrop filter for the tab-bar lens (Chromium): magnifies whatever is under the droplet,
 * the page behind the bar as well as the tab icons, and bends it at the rim with a faint
 * colour fringe.
 */
export function ensureLensBackdropFilter(w: number, h: number) {
  w = Math.round(w);
  h = Math.round(h);
  const id = lensBackdropId(w, h);
  if (w < 8 || h < 8 || document.getElementById(id)) return;
  const { url, scale } = drawLensMap(w, h, 1.2, Math.min(12, h / 4), 7);
  const ch = (s: number, keep: 0 | 1 | 2, result: string) => {
    const m = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0];
    m[keep * 6] = 1;
    return [
      el("feDisplacementMap", { in: "SourceGraphic", in2: "map", scale: s, xChannelSelector: "R", yChannelSelector: "G", result: `${result}-d` }),
      el("feColorMatrix", { in: `${result}-d`, type: "matrix", values: m.join(" "), result }),
    ];
  };
  sharedDefs().appendChild(
    el(
      "filter",
      { id, x: 0, y: 0, width: w, height: h, filterUnits: "userSpaceOnUse", primitiveUnits: "userSpaceOnUse", "color-interpolation-filters": "sRGB" },
      el("feImage", { href: url, x: 0, y: 0, width: w, height: h, preserveAspectRatio: "none", result: "map" }),
      ...ch(scale * 1.03, 0, "r"),
      ...ch(scale, 1, "g"),
      ...ch(scale * 0.97, 2, "b"),
      el("feBlend", { in: "r", in2: "g", mode: "screen", result: "rg" }),
      el("feBlend", { in: "rg", in2: "b", mode: "screen", result: "rgb" }),
      el("feColorMatrix", { in: "rgb", type: "saturate", values: 1.25 }),
    ),
  );
}

export function LiquidGlass() {
  useEffect(() => {
    if (!supported()) return;
    document.documentElement.dataset.liquidGlass = "";

    const svg = el("svg", { width: 0, height: 0, "aria-hidden": "true", style: "position:absolute;width:0;height:0;overflow:hidden" });
    const defs = el("defs", {});
    svg.appendChild(defs);
    document.body.appendChild(svg);
    const made = new Set<string>();

    const apply = (node: HTMLElement) => {
      const rect = node.getBoundingClientRect();
      // Untransformed size: transforms (press, lens) scale the filter along with the element.
      const w = Math.round(node.offsetWidth || rect.width);
      const h = Math.round(node.offsetHeight || rect.height);
      if (w < 8 || h < 8) return;
      const radius = Math.min(parseFloat(getComputedStyle(node).borderTopLeftRadius) || 0, w / 2, h / 2);
      const kind: Kind = node.classList.contains("glass-bar") ? "bar" : node.classList.contains("glass-clear") ? "clear" : "frosted";
      const id = `lg-${kind}-${w}x${h}-${Math.round(radius)}`;
      if (!made.has(id)) {
        made.add(id);
        defs.appendChild(buildFilter(id, w, h, Math.max(radius, 0.5), kind));
      }
      const value = `url(#${id})`;
      if (node.style.backdropFilter !== value) node.style.backdropFilter = value;
    };

    const ro = new ResizeObserver((entries) => entries.forEach((e) => apply(e.target as HTMLElement)));
    const watched = new WeakSet<Element>();
    const scan = () => {
      document.querySelectorAll<HTMLElement>(SELECTOR).forEach((node) => {
        if (watched.has(node)) return;
        watched.add(node);
        ro.observe(node);
      });
    };

    let queued = 0;
    const mo = new MutationObserver(() => {
      if (queued) return;
      queued = requestAnimationFrame(() => { queued = 0; scan(); });
    });
    mo.observe(document.body, { childList: true, subtree: true });
    scan();

    return () => {
      mo.disconnect();
      ro.disconnect();
      cancelAnimationFrame(queued);
      svg.remove();
      delete document.documentElement.dataset.liquidGlass;
    };
  }, []);

  return null;
}
