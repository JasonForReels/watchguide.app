"use client";

import { useEffect } from "react";
import { getState, useStore, type State } from "./store";

/**
 * Browser side of reminders. A device is identified by its push subscription (no account needed).
 * The server keeps the subscription plus the TMDB IDs of followed shows and saved films, and
 * `usePushSync` re-sends them whenever the lists change.
 */
export const VAPID_PUBLIC_KEY = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY ?? "";

export type PushStatus = "unsupported" | "needs-install" | "denied" | "off" | "on";

/** Watchlist titles (shows and films) plus shows with watched episodes, as "tv-1" / "movie-2" keys. */
export function followedKeys(s: State): string[] {
  const out = new Set<string>();
  for (const i of s.lists.want) out.add(i.key);
  for (const id of Object.keys(s.episodes)) {
    if (!s.lists.watched.some((i) => i.key === `tv-${id}`)) out.add(`tv-${id}`);
  }
  return [...out].sort();
}

const isIOS = () => /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
const isStandalone = () => matchMedia("(display-mode: standalone)").matches || (navigator as { standalone?: boolean }).standalone === true;

function supported() {
  return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window;
}

async function currentSubscription(): Promise<PushSubscription | null> {
  if (!supported()) return null;
  const reg = await navigator.serviceWorker.getRegistration("/");
  return (await reg?.pushManager.getSubscription()) ?? null;
}

export async function pushStatus(): Promise<PushStatus> {
  if (!supported()) return isIOS() && !isStandalone() ? "needs-install" : "unsupported";
  if (Notification.permission === "denied") return "denied";
  return (await currentSubscription()) && Notification.permission === "granted" ? "on" : "off";
}

function keyBytes(b64: string) {
  const pad = "=".repeat((4 - (b64.length % 4)) % 4);
  const raw = atob((b64 + pad).replace(/-/g, "+").replace(/_/g, "/"));
  return Uint8Array.from(raw, (c) => c.charCodeAt(0));
}

async function post(path: string, body: unknown) {
  const res = await fetch(path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  if (!res.ok) throw new Error(((await res.json().catch(() => null)) as { error?: string } | null)?.error ?? "Couldn't reach WatchGuide.");
}

export async function syncSubscription(sub: PushSubscription) {
  await post("/api/push/sync", { subscription: sub.toJSON(), ids: followedKeys(getState()) });
}

/** Must be called from a tap: it triggers the browser's permission prompt. */
export async function enablePush(): Promise<PushStatus> {
  if (!supported() || !VAPID_PUBLIC_KEY) return pushStatus();
  const permission = await Notification.requestPermission();
  if (permission !== "granted") return pushStatus();
  const reg = (await navigator.serviceWorker.getRegistration("/")) ?? (await navigator.serviceWorker.register("/sw.js", { scope: "/" }));
  await navigator.serviceWorker.ready;
  const sub =
    (await reg.pushManager.getSubscription()) ??
    (await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(VAPID_PUBLIC_KEY) }));
  await syncSubscription(sub);
  notify();
  return "on";
}

export async function disablePush(): Promise<PushStatus> {
  const sub = await currentSubscription();
  if (sub) {
    await post("/api/push/unsubscribe", { endpoint: sub.endpoint }).catch(() => {});
    await sub.unsubscribe();
  }
  notify();
  return pushStatus();
}

const listeners = new Set<() => void>();
const notify = () => listeners.forEach((l) => l());
export const subscribeToPush = (l: () => void) => (listeners.add(l), () => void listeners.delete(l));

/** Keeps the server's copy of this device's followed titles current. Mount once, app-wide. */
export function usePushSync() {
  const keys = useStore((s) => followedKeys(s).join(","));
  useEffect(() => {
    if (!supported() || Notification.permission !== "granted") return;
    const t = setTimeout(async () => {
      const sub = await currentSubscription();
      if (sub) syncSubscription(sub).catch(() => {});
    }, 1500);
    return () => clearTimeout(t);
  }, [keys]);
}
