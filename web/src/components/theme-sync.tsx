"use client";

import { useEffect } from "react";
import { useHydrated, useStore } from "@/lib/store";
import { themeById } from "@/lib/themes";

/** Keeps <html> attributes in step with settings after the boot script runs. */
export function ThemeSync() {
  const theme = useStore((s) => s.settings.theme);
  const scheme = useStore((s) => s.settings.scheme);
  const hydrated = useHydrated();
  const active = themeById(theme);

  useEffect(() => {
    // Before hydration the store reports defaults; the boot script already set the real theme.
    if (!hydrated) return;
    const root = document.documentElement;
    root.dataset.theme = active.id;
    root.dataset.frame = active.frame;
    if (scheme === "system") delete root.dataset.scheme;
    else root.dataset.scheme = scheme;
  }, [hydrated, active, scheme]);

  return null;
}
