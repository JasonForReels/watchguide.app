"use client";

import { useEffect, useState } from "react";
import { Download } from "lucide-react";

interface InstallPromptEvent extends Event {
  prompt(): Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
}

let deferred: InstallPromptEvent | null = null;
const listeners = new Set<() => void>();

/** Registers the service worker and keeps the Android browser bar in step with the theme. */
export function PWA() {
  useEffect(() => {
    if ("serviceWorker" in navigator && process.env.NODE_ENV === "production") {
      navigator.serviceWorker.register("/sw.js", { scope: "/", updateViaCache: "none" }).catch(() => {});
    }
    const onPrompt = (e: Event) => {
      e.preventDefault();
      deferred = e as InstallPromptEvent;
      listeners.forEach((l) => l());
    };
    const onInstalled = () => {
      deferred = null;
      listeners.forEach((l) => l());
    };
    window.addEventListener("beforeinstallprompt", onPrompt);
    window.addEventListener("appinstalled", onInstalled);

    // Match the status bar to the active theme's background.
    const meta = () => document.querySelector<HTMLMetaElement>('meta[name="theme-color"]');
    const sync = () => {
      const bg = getComputedStyle(document.documentElement).getPropertyValue("--bg").trim();
      const m = meta();
      if (bg && m) m.content = bg;
    };
    sync();
    const obs = new MutationObserver(sync);
    obs.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme", "data-scheme"] });
    const mq = matchMedia("(prefers-color-scheme: light)");
    mq.addEventListener("change", sync);

    return () => {
      window.removeEventListener("beforeinstallprompt", onPrompt);
      window.removeEventListener("appinstalled", onInstalled);
      obs.disconnect();
      mq.removeEventListener("change", sync);
    };
  }, []);
  return null;
}

/** "Install app" row, shown only when the browser offers installation (Chrome on Android, desktop Chrome/Edge). */
export function InstallButton() {
  const [available, setAvailable] = useState(false);
  useEffect(() => {
    const update = () => setAvailable(deferred !== null);
    update();
    listeners.add(update);
    return () => void listeners.delete(update);
  }, []);
  if (!available) return null;

  return (
    <button
      type="button"
      onClick={async () => {
        if (!deferred) return;
        await deferred.prompt();
        await deferred.userChoice;
        deferred = null;
        listeners.forEach((l) => l());
      }}
      className="press mx-4 mb-7 flex w-[calc(100%-2rem)] items-center gap-4 rounded-[22px] bg-tint px-4 py-3.5 text-left text-white sm:mx-8 sm:w-[calc(100%-4rem)]"
    >
      <span className="grid size-10 place-items-center rounded-xl bg-black/10"><Download className="size-5" /></span>
      <span><span className="block font-semibold">Install WatchGuide</span><span className="text-sm opacity-80">Add it to your home screen</span></span>
    </button>
  );
}
