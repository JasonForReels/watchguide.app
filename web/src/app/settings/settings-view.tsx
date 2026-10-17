"use client";

import Link from "next/link";
import { useEffect, useRef, useState } from "react";
import { Bell, Check, ChevronRight, Download, Film, Gift, Upload } from "lucide-react";
import { ProCard } from "@/components/pro-gate";
import { PageHeader } from "@/components/rail";
import { REGIONS } from "@/lib/catalog";
import { disablePush, enablePush, pushStatus, subscribeToPush, VAPID_PUBLIC_KEY, type PushStatus } from "@/lib/push-client";
import { actions, getState, useHydrated, useStore } from "@/lib/store";
import { PACKS, THEMES, themeById, type Theme } from "@/lib/themes";

function Swatch({ t }: { t: Theme }) {
  return (
    <span className="flex h-8 w-14 shrink-0 overflow-hidden rounded-md ring-1 ring-line">
      {[t.dark[0], t.dark[2], t.dark[3]].map((c) => <span key={c} className="flex-1" style={{ background: `#${c}` }} />)}
    </span>
  );
}

function Section({ title, children, footer }: { title: string; children: React.ReactNode; footer?: React.ReactNode }) {
  return (
    <section>
      <h2 className="mb-2 px-1 text-sm font-semibold text-muted">{title}</h2>
      <div className="divide-y divide-line overflow-hidden rounded-card bg-surface">{children}</div>
      {footer && <p className="mt-2 px-1 text-xs leading-relaxed text-faint">{footer}</p>}
    </section>
  );
}

export function SettingsView() {
  const hydrated = useHydrated();
  const settings = useStore((s) => s.settings);
  const [preview, setPreview] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const file = useRef<HTMLInputElement>(null);
  const current = themeById(settings.theme);

  // A "Try" preview lasts until you leave Settings.
  useEffect(() => {
    const root = document.documentElement;
    const t = themeById(preview ?? settings.theme);
    root.dataset.theme = t.id;
    root.dataset.frame = t.frame;
  }, [preview, settings.theme]);
  useEffect(() => () => {
    const t = themeById(getState().settings.theme);
    document.documentElement.dataset.theme = t.id;
    document.documentElement.dataset.frame = t.frame;
  }, []);

  const exportBackup = () => {
    const blob = new Blob([actions.exportJSON()], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `watchguide-backup-${new Date().toISOString().slice(0, 10)}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const importBackup = async (f: File) => {
    try {
      actions.importJSON(await f.text());
      setMessage("Backup restored.");
    } catch (e) {
      setMessage((e as Error).message || "That file couldn't be read.");
    }
  };

  const shown = themeById(preview ?? settings.theme);

  return (
    <div className="pb-10">
      <PageHeader title="Settings" />
      <div className="mx-auto max-w-2xl space-y-8 px-4 sm:px-8">
        <ProCard />
        <Section title="Theme">
          <div className="p-5">
            <div className="flex gap-3">
              {[0, 1, 2, 3].map((i) => (
                <div
                  key={i}
                  className="aspect-[2/3] flex-1 rounded-card"
                  style={{
                    background: `linear-gradient(to bottom, #${shown.dark[1]}, #${i % 2 ? shown.dark[3] : shown.dark[2]})`,
                    boxShadow: shown.frame === "none" ? "none" : `0 0 0 ${shown.frame === "marquee" ? 3 : 1.5}px #${shown.dark[2]}${shown.frame === "glow" ? `, 0 0 18px -4px #${shown.dark[2]}` : ""}`,
                  }}
                />
              ))}
            </div>
            <p className="mt-4 font-display text-2xl font-bold">{shown.name}</p>
            <p className="text-secondary">{shown.mood}</p>
            {preview && preview !== settings.theme && (
              <div className="mt-3 flex items-center gap-3 text-sm">
                <span className="text-muted">Previewing. Leaving Settings switches back.</span>
                <button type="button" onClick={() => setPreview(null)} className="font-medium text-accent">Stop preview</button>
              </div>
            )}
          </div>
          {THEMES.filter((t) => t.pack === "free").map((t) => (
            <button key={t.id} type="button" onClick={() => { actions.updateSettings({ theme: t.id }); setPreview(null); }} className="flex w-full items-center gap-4 px-5 py-3.5 text-left hover:bg-raised/40">
              <Swatch t={t} />
              <span className="flex-1"><span className="block font-medium text-accent">{t.name}</span><span className="text-sm text-muted">{t.mood}</span></span>
              {hydrated && current.id === t.id && <Check className="size-5 text-accent" />}
            </button>
          ))}
        </Section>

        {PACKS.map((pack) => (
          <Section key={pack.id} title={pack.name} footer={pack.id === "cinema" ? "Theme packs are bought in the WatchGuide iOS app. On the web you can preview any of them." : undefined}>
            <div className="flex items-start gap-4 p-5">
              <span className="grid size-10 shrink-0 place-items-center rounded-xl bg-accent/15 text-accent">{pack.id === "cinema" ? <Film className="size-5" /> : <Gift className="size-5" />}</span>
              <div className="flex-1">
                <p className="font-semibold">{pack.name}</p>
                <p className="text-sm text-muted">{pack.tagline}</p>
              </div>
              <span className="rounded-full bg-accent px-3 py-1 text-sm font-semibold text-on-accent">{pack.price}</span>
            </div>
            {THEMES.filter((t) => t.pack === pack.id).map((t) => (
              <div key={t.id} className="flex items-center gap-4 px-5 py-3.5">
                <Swatch t={t} />
                <span className="min-w-0 flex-1"><span className="block font-medium">{t.name}</span><span className="block truncate text-sm text-muted">{t.mood}</span></span>
                <button type="button" onClick={() => setPreview(t.id)} className={`text-sm font-semibold ${preview === t.id ? "text-text" : "text-accent"}`}>
                  {preview === t.id ? "Previewing" : "Try"}
                </button>
              </div>
            ))}
          </Section>
        ))}

        <Section title="Appearance">
          <div className="flex gap-1 p-2">
            {(["system", "dark", "light"] as const).map((s) => (
              <button key={s} type="button" onClick={() => actions.updateSettings({ scheme: s })} className={`flex-1 rounded-lg py-2 text-sm capitalize transition ${hydrated && settings.scheme === s ? "bg-accent font-semibold text-on-accent" : "text-muted hover:text-text"}`}>
                {s === "system" ? "Automatic" : s}
              </button>
            ))}
          </div>
        </Section>

        <Section title="Trailers" footer="Trailers start muted unless you turn that off. Your mute choice carries across Browse, title pages and Pops.">
          {([
            ["autoPlayTrailers", "Auto-play Trailers"],
            ["trailersMuted", "Mute Trailers on Autoplay"],
            ["showTrailersInDetails", "Show Trailers in Media Details"],
          ] as const).map(([k, label]) => (
            <label key={k} className="flex cursor-pointer items-center justify-between px-5 py-3.5">
              <span>{label}</span>
              <Switch on={hydrated && settings[k]} onChange={(v) => actions.updateSettings({ [k]: v })} label={label} />
            </label>
          ))}
        </Section>

        <Reminders />

        <Section title="Streaming" footer="Your region decides which services and release dates you see.">
          <label className="flex items-center justify-between px-5 py-3.5">
            <span>Region</span>
            <select value={settings.region} onChange={(e) => actions.updateSettings({ region: e.target.value })} className="rounded-lg bg-bg px-2.5 py-1.5 text-sm ring-1 ring-line outline-none">
              {REGIONS.map((r) => <option key={r.code} value={r.code}>{r.name}</option>)}
            </select>
          </label>
          <Link href="/streamq" className="flex items-center justify-between px-5 py-3.5 hover:bg-raised/40">
            <span>My services</span>
            <span className="flex items-center gap-1 text-sm text-muted">{hydrated ? settings.services.length : 0} selected <ChevronRight className="size-4" /></span>
          </Link>
        </Section>

        <Section title="Your data" footer="Lists, ratings and progress are stored in this browser only. Export a backup to move them to another browser.">
          <button type="button" onClick={exportBackup} className="flex w-full items-center gap-3 px-5 py-3.5 text-left hover:bg-raised/40"><Download className="size-4 text-accent" /> Export backup</button>
          <button type="button" onClick={() => file.current?.click()} className="flex w-full items-center gap-3 px-5 py-3.5 text-left hover:bg-raised/40"><Upload className="size-4 text-accent" /> Import backup</button>
          <input ref={file} type="file" accept="application/json" hidden onChange={(e) => e.target.files?.[0] && importBackup(e.target.files[0])} />
          <button
            type="button"
            onClick={() => {
              if (confirm("Erase all lists, ratings, progress and settings in this browser? Export a backup first if you want to keep them.")) {
                actions.reset();
                setMessage("Everything was erased.");
              }
            }}
            className="w-full px-5 py-3.5 text-left text-red-400 hover:bg-raised/40"
          >
            Erase all data
          </button>
        </Section>
        {message && <p className="text-center text-sm text-muted" role="status">{message}</p>}

        <p className="pt-4 text-center text-xs leading-relaxed text-faint">
          WatchGuide for the web. Film and TV data from TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB. Streaming availability by JustWatch.
        </p>
      </div>
    </div>
  );
}

/** iOS-style switch. */
function Switch({ on, onChange, label }: { on: boolean; onChange: (v: boolean) => void; label: string }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={on}
      aria-label={label}
      onClick={() => onChange(!on)}
      className={`relative h-[31px] w-[51px] shrink-0 rounded-full transition-colors duration-200 ${on ? "bg-[#34c759]" : "bg-text/20"}`}
    >
      <span className={`absolute top-[2px] left-[2px] size-[27px] rounded-full bg-white shadow-md transition-transform duration-200 ${on ? "translate-x-5" : ""}`} />
    </button>
  );
}

const REMINDER_NOTE: Record<PushStatus, string> = {
  unsupported: "This browser can't show notifications.",
  "needs-install": "On iPhone and iPad, notifications only work once WatchGuide is added to your Home Screen: tap Share, then Add to Home Screen, and open it from there.",
  denied: "Notifications are blocked for this site. Allow them in your browser's site settings, then come back.",
  off: "Get a notification the day a show you follow has a new episode, or a film you saved is released. No account needed; this device is remembered by its notification subscription.",
  on: "On for this device. Reminders follow your Watching and Want to Watch lists and update when you change them.",
};

function Reminders() {
  const [status, setStatus] = useState<PushStatus | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const refresh = () => void pushStatus().then(setStatus);
    refresh();
    return subscribeToPush(refresh);
  }, []);

  const toggle = async (on: boolean) => {
    setBusy(true);
    setError(null);
    try {
      setStatus(on ? await enablePush() : await disablePush());
    } catch (e) {
      setError((e as Error).message || "Couldn't change reminders.");
    } finally {
      setBusy(false);
    }
  };

  const usable = status === "off" || status === "on";
  return (
    <Section title="Reminders" footer={error ?? (status ? REMINDER_NOTE[status] : undefined)}>
      <div className="flex items-center justify-between gap-4 px-5 py-3.5">
        <span className="flex items-center gap-3"><Bell className="size-4 text-accent" /> Episode and release reminders</span>
        <Switch on={status === "on"} onChange={(v) => { if (usable && !busy && VAPID_PUBLIC_KEY) void toggle(v); }} label="Episode and release reminders" />
      </div>
    </Section>
  );
}
