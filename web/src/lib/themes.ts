/** Ported from `Models/ThemePack.swift`. Palettes are [background, surface, accent, secondary, text]. */
export type FrameStyle = "none" | "hairline" | "marquee" | "filmStrip" | "glow";

export interface Theme {
  id: string;
  name: string;
  mood: string;
  light: string[];
  dark: string[];
  radius: number;
  frame: FrameStyle;
  pack: "free" | "cinema" | "holidays";
}

export const THEMES: Theme[] = [
  { id: "marquee", name: "Marquee", mood: "House lights down, posters up.", pack: "free",
    light: ["F6F1E9", "FFFFFF", "FF9E33", "8A6A4A", "1C1714"], dark: ["000000", "1C1C1E", "FF9E33", "C9A77C", "FFFFFF"], radius: 14, frame: "marquee" },
  { id: "drive-in", name: "Drive-In", mood: "Retro summer night at an outdoor cinema.", pack: "cinema",
    light: ["F3F0FA", "FFFFFF", "D6249F", "1BA8C4", "1B1640"], dark: ["120E33", "1E1850", "FF3EC8", "2EE6FF", "FFF8F0"], radius: 20, frame: "glow" },
  { id: "noir", name: "Noir", mood: "Rain-soaked, late-night detective film.", pack: "cinema",
    light: ["EDEDED", "FFFFFF", "B7791F", "5E5E5E", "111111"], dark: ["0A0A0A", "1C1C1C", "E0A040", "A8A8A8", "E8E8E8"], radius: 4, frame: "hairline" },
  { id: "golden-age", name: "Golden Age", mood: "Lavish classic-Hollywood colour.", pack: "cinema",
    light: ["FFF9EC", "FFFFFF", "B3122E", "007A8A", "2A1A10"], dark: ["1F0A0E", "2E1216", "E8334F", "2EC4D6", "FFF6E0"], radius: 10, frame: "marquee" },
  { id: "scifi-terminal", name: "Sci-Fi Terminal", mood: "A computer terminal on a starship.", pack: "cinema",
    light: ["EEF6F2", "FFFFFF", "0F8F4A", "0A8FB0", "0C1A14"], dark: ["05080A", "0D1418", "39FF88", "2EE6FF", "C8F5DC"], radius: 2, frame: "glow" },
  { id: "art-house", name: "Art House", mood: "Quiet, minimal gallery cinema.", pack: "cinema",
    light: ["FAF6EE", "FFFFFF", "A8432E", "6B6B6B", "262626"], dark: ["1E1D1B", "2A2826", "D9694F", "A3A09A", "F5F0E6"], radius: 0, frame: "none" },
  { id: "creature-feature", name: "Creature Feature", mood: "Midnight monster-movie marathon.", pack: "holidays",
    light: ["F4F0F7", "FFFFFF", "D9531E", "3E9E3E", "1A1024"], dark: ["120A1A", "20142C", "FF6A2B", "7CFF6B", "F2EDE4"], radius: 12, frame: "filmStrip" },
  { id: "festive-feature", name: "Festive Feature", mood: "Warm, sparkly, no snow required.", pack: "holidays",
    light: ["FFF8EC", "FFFFFF", "A3122A", "1F5C3A", "2A1810"], dark: ["14201A", "1E2E25", "E0B04A", "E0485C", "FFF5E1"], radius: 16, frame: "glow" },
  { id: "premiere-night", name: "Premiere Night", mood: "Midnight countdown, red carpet.", pack: "holidays",
    light: ["FBF6EA", "FFFFFF", "9C7A1E", "8E1B2B", "151515"], dark: ["0B0B0B", "1A1714", "E6C35C", "D0344A", "F7E9C8"], radius: 8, frame: "marquee" },
];

export const PACKS = [
  { id: "cinema", name: "Cinema Pack", tagline: "Now-playing sync, scheduling, Marathon mode and five core themes.", price: "$9.99" },
  { id: "holidays", name: "Holidays", tagline: "Festive looks that work in both hemispheres.", price: "$4.99" },
] as const;

export const themeById = (id: string) => THEMES.find((t) => t.id === id) ?? THEMES[0];

function vars(p: string[], radius: number): string {
  const [bg, surface, accent, secondary, text] = p.map((c) => `#${c}`);
  return `--bg:${bg};--surface:${surface};--accent:${accent};--secondary:${secondary};--text:${text};--radius:${radius}px;`;
}

/** CSS for every theme, light and dark, keyed off `data-theme` and `data-scheme` on <html>. */
export function themeCSS(): string {
  return THEMES.map((t) => {
    const sel = `:root[data-theme="${t.id}"]`;
    return [
      `${sel}{${vars(t.dark, t.radius)}color-scheme:dark;}`,
      `${sel}[data-scheme="light"]{${vars(t.light, t.radius)}color-scheme:light;}`,
      `@media (prefers-color-scheme: light){${sel}:not([data-scheme="dark"]){${vars(t.light, t.radius)}color-scheme:light;}}`,
    ].join("");
  }).join("\n");
}
