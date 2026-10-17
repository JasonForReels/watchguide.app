"use client";

/**
 * WatchGuide Pro on the web: Paddle takes the payment, RevenueCat owns the entitlement.
 *
 * Mirrors ScoutSubscriptionService on iOS: the same project and the same `watchguide_pro`
 * entitlement, so a web purchase is the same Pro. Paddle.js opens the checkout; when it
 * completes we hand the transaction to RevenueCat through /api/pro, which unlocks Pro at once
 * (Paddle's webhook reaches RevenueCat too, and the two agree on the same transaction).
 * There are no accounts yet, so each browser gets an anonymous RevenueCat user ID; a web
 * purchase unlocks Pro in that browser. Linking it to the iOS app needs sign-in (see README).
 */

import { useSyncExternalStore } from "react";
import type { Paddle } from "@paddle/paddle-js";

/** The entitlement every Pro product is attached to in RevenueCat (ScoutSubscriptionService.proEntitlementID). */
export const PRO_ENTITLEMENT = "watchguide_pro";

/** Free-tier limits, from AIMessageQuota.swift. */
export const FREE_LIMITS = { atlasMessagesPerDay: 5, customLists: 3 } as const;

const CLIENT_TOKEN = process.env.NEXT_PUBLIC_PADDLE_CLIENT_TOKEN ?? "";
const PADDLE_ENV = process.env.NEXT_PUBLIC_PADDLE_ENV === "production" ? "production" : "sandbox";
const PRICE_IDS = {
  annual: process.env.NEXT_PUBLIC_PADDLE_PRICE_ANNUAL ?? "",
  monthly: process.env.NEXT_PUBLIC_PADDLE_PRICE_MONTHLY ?? "",
} as const;
const ENABLED = !!CLIENT_TOKEN && !!(PRICE_IDS.annual || PRICE_IDS.monthly);

const USER_KEY = "watchguide.rc_user";
const PRO_CACHE_KEY = "watchguide.pro";

export type ProStatus = "unavailable" | "loading" | "free" | "pro";

interface ProState {
  status: ProStatus;
  /** Where to manage or cancel the subscription (Paddle's customer portal, via RevenueCat). */
  managementURL: string | null;
  expires: Date | null;
  willRenew: boolean;
  sandbox: boolean;
}

let state: ProState = { status: ENABLED ? "loading" : "unavailable", managementURL: null, expires: null, willRenew: false, sandbox: false };
const listeners = new Set<() => void>();
const emit = (next: Partial<ProState>) => {
  state = { ...state, ...next };
  listeners.forEach((l) => l());
};

function storage(): Storage | null {
  try { return window.localStorage; } catch { return null; }
}

/** This browser's anonymous RevenueCat user ID, made once. */
function userId(): string {
  const ls = storage();
  let id = ls?.getItem(USER_KEY) ?? null;
  if (!id) {
    id = `$RCAnonymousID:${crypto.randomUUID().replaceAll("-", "")}`;
    ls?.setItem(USER_KEY, id);
  }
  return id;
}

interface ProReply { pro: boolean; expires: string | null; willRenew: boolean; managementURL: string | null; sandbox: boolean }

function apply(r: ProReply) {
  storage()?.setItem(PRO_CACHE_KEY, r.pro ? "1" : "0");
  emit({
    status: r.pro ? "pro" : "free",
    managementURL: r.managementURL,
    expires: r.expires ? new Date(r.expires) : null,
    willRenew: r.willRenew,
    sandbox: r.sandbox,
  });
}

/** Re-reads the entitlement from RevenueCat. */
export async function refreshPro() {
  if (!ENABLED || typeof window === "undefined") return;
  try {
    const res = await fetch(`/api/pro?uid=${encodeURIComponent(userId())}`, { cache: "no-store" });
    if (!res.ok) throw new Error(String(res.status));
    apply((await res.json()) as ProReply);
  } catch {
    // Offline or blocked: keep the last known answer rather than locking someone out.
    if (state.status === "loading") emit({ status: storage()?.getItem(PRO_CACHE_KEY) === "1" ? "pro" : "free" });
  }
}

let started = false;
function start() {
  if (started || typeof window === "undefined") return;
  started = true;
  // Show the cached answer straight away, then confirm it, as iOS does with UserDefaults.
  if (ENABLED && storage()?.getItem(PRO_CACHE_KEY) === "1") emit({ status: "pro" });
  void refreshPro();
  document.addEventListener("visibilitychange", () => { if (!document.hidden) void refreshPro(); });
}

/** Current Pro state. Free until hydrated, so server and first client render agree. */
export function usePro(): ProState & { isPro: boolean } {
  const s = useSyncExternalStore(
    (l) => { start(); listeners.add(l); return () => listeners.delete(l); },
    () => state,
    () => SERVER_STATE,
  );
  return { ...s, isPro: s.status === "pro" };
}
const SERVER_STATE: ProState = { status: "loading", managementURL: null, expires: null, willRenew: false, sandbox: false };

// MARK: - Paddle

let paddle: Promise<Paddle | undefined> | null = null;
/** Resolves with the completed transaction's ID when a checkout finishes, or null if it was closed. */
let onCheckoutDone: ((transactionId: string | null) => void) | null = null;

function loadPaddle(): Promise<Paddle | undefined> {
  paddle ??= import("@paddle/paddle-js").then(({ initializePaddle }) =>
    initializePaddle({
      environment: PADDLE_ENV,
      token: CLIENT_TOKEN,
      eventCallback: (e) => {
        if (e.name === "checkout.completed") onCheckoutDone?.(e.data?.transaction_id ?? null);
        else if (e.name === "checkout.closed") onCheckoutDone?.(null);
      },
    }),
  );
  return paddle;
}

export type PlanId = "annual" | "monthly";

export interface Plan {
  id: PlanId;
  /** Price per billing period, in the buyer's currency, as Paddle formats it ("$25.49"). */
  formatted: string;
  /** Raw amount in major units, and the ISO currency, for per-month maths. */
  amount: number;
  currency: string;
  trialDays: number;
}

const DAYS = { day: 1, week: 7, month: 30, year: 365 } as const;

/** The plans the paywall shows, priced for the buyer's country by Paddle. */
export async function getPlans(): Promise<Plan[]> {
  const p = ENABLED ? await loadPaddle() : undefined;
  if (!p) return [];
  const ids = (["annual", "monthly"] as const).filter((id) => PRICE_IDS[id]);
  const preview = await p.PricePreview({ items: ids.map((id) => ({ priceId: PRICE_IDS[id], quantity: 1 })) });
  return preview.data.details.lineItems.flatMap((li) => {
    const id = ids.find((i) => PRICE_IDS[i] === li.price.id);
    if (!id) return [];
    const trial = li.price.trialPeriod;
    return [{
      id,
      formatted: li.formattedTotals.total,
      amount: Number(li.totals.total) / 10 ** (new Intl.NumberFormat(undefined, { style: "currency", currency: preview.data.currencyCode }).resolvedOptions().maximumFractionDigits ?? 2),
      currency: preview.data.currencyCode,
      trialDays: trial ? trial.frequency * DAYS[trial.interval] : 0,
    }];
  });
}

export type PurchaseOutcome = "purchased" | "cancelled" | { error: string };

/** Opens Paddle's checkout for a plan, then tells RevenueCat so Pro unlocks. */
export async function buy(plan: PlanId): Promise<PurchaseOutcome> {
  const p = ENABLED ? await loadPaddle() : undefined;
  if (!p || !PRICE_IDS[plan]) return { error: "Purchases aren't set up on this site yet." };
  const uid = userId();

  const done = new Promise<string | null>((resolve) => { onCheckoutDone = resolve; });
  p.Checkout.open({
    items: [{ priceId: PRICE_IDS[plan], quantity: 1 }],
    // RevenueCat reads the buyer's ID from the transaction's custom data (rc_user_id).
    customData: { rc_user_id: uid },
    settings: { displayMode: "overlay", theme: "dark", variant: "one-page" },
  });
  const transactionId = await done;
  onCheckoutDone = null;
  if (!transactionId) return "cancelled";

  try {
    const res = await fetch("/api/pro", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ uid, transactionId }),
    });
    if (!res.ok) throw new Error(String(res.status));
    const reply = (await res.json()) as ProReply;
    apply(reply);
    if (reply.pro) return "purchased";
  } catch {
    // Fall through: the webhook may still land.
  }
  // Paid, but RevenueCat hasn't caught up. Check a few times before giving up.
  for (let i = 0; i < 5; i++) {
    await new Promise((r) => setTimeout(r, 2000));
    await refreshPro();
    if (state.status === "pro") return "purchased";
  }
  return { error: "Your payment went through, but Pro hasn't switched on yet. Reopen this page in a minute." };
}

// MARK: - Free-tier quota for Atlas, per day in this browser (AIMessageQuota on iOS).

const ATLAS_KEY = "watchguide.atlas_quota";
const today = () => new Date().toISOString().slice(0, 10);

export function atlasMessagesLeft(): number {
  try {
    const q = JSON.parse(storage()?.getItem(ATLAS_KEY) ?? "null") as { day: string; used: number } | null;
    const used = q?.day === today() ? q.used : 0;
    return Math.max(0, FREE_LIMITS.atlasMessagesPerDay - used);
  } catch {
    return FREE_LIMITS.atlasMessagesPerDay;
  }
}

export function consumeAtlasMessage() {
  const used = FREE_LIMITS.atlasMessagesPerDay - atlasMessagesLeft() + 1;
  storage()?.setItem(ATLAS_KEY, JSON.stringify({ day: today(), used }));
}

/** Free accounts get three custom lists, as on iOS (AIMessageQuota.freeCustomLists). */
export function canCreateList(isPro: boolean, status: ProStatus, count: number) {
  return isPro || status === "unavailable" || count < FREE_LIMITS.customLists;
}
