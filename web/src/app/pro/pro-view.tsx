"use client";

import { useEffect, useMemo, useState } from "react";
import { BarChart3, Check, Clapperboard, Film, Folder, Link2, Loader2, Map as MapIcon, MessagesSquare, Sparkles } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { BackButton } from "@/components/rail";
import { buy, getPlans, usePro } from "@/lib/purchases";
import type { Plan } from "@/lib/purchases";

/** Same benefits, same order as WGUnlimitedPaywallView. */
const BENEFITS: { icon: LucideIcon; title: string; detail: string }[] = [
  { icon: MessagesSquare, title: "Ask Atlas anything", detail: "Unlimited questions about any film or show" },
  { icon: Film, title: "Post-credits checks", detail: "Know before you leave your seat" },
  { icon: MapIcon, title: "Cinema trip planning", detail: "Live traffic tells you when to leave" },
  { icon: Folder, title: "Unlimited lists", detail: "Organize everything, no cap" },
  { icon: Sparkles, title: "AI playlists & share cards", detail: "Curated picks worth sharing" },
  { icon: BarChart3, title: "Stats & insights", detail: "Your watching, properly measured" },
  { icon: Link2, title: "Instant deep links", detail: "Jump straight into the right app" },
];

const money = (amount: number, currency: string) =>
  new Intl.NumberFormat(undefined, { style: "currency", currency }).format(amount);

export function ProView() {
  const pro = usePro();
  const [plans, setPlans] = useState<Plan[] | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [selected, setSelected] = useState<"annual" | "monthly">("annual");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    if (pro.status === "unavailable") return;
    let live = true;
    getPlans()
      .then((p) => { if (live) setPlans(p); })
      .catch((e) => { if (live) setLoadError(e instanceof Error ? e.message : "Couldn't load plans."); });
    return () => { live = false; };
  }, [pro.status]);

  const annual = plans?.find((p) => p.id === "annual") ?? null;
  const monthly = plans?.find((p) => p.id === "monthly") ?? null;
  const plan: Plan | null = selected === "annual" ? annual ?? monthly : monthly ?? annual;

  const savings = useMemo(() => {
    if (!annual || !monthly || monthly.amount <= 0) return null;
    const pct = Math.round((1 - annual.amount / (monthly.amount * 12)) * 100);
    return pct > 0 ? pct : null;
  }, [annual, monthly]);

  const trialDays = annual?.trialDays ?? 0;
  const annualPrice = annual?.formatted;
  const monthlyPrice = monthly?.formatted;
  const showsTrial = selected === "annual" && trialDays > 0;

  const purchase = async () => {
    if (!plan) return;
    setBusy(true);
    setMessage(null);
    const result = await buy(plan.id);
    setBusy(false);
    if (result === "purchased") setMessage("Welcome to WatchGuide Pro.");
    else if (result !== "cancelled") setMessage(result.error);
  };

  return (
    <div className="mx-auto max-w-xl px-4 pt-4 pb-16 md:pt-3">
      <div className="mb-6 flex items-center gap-3">
        <BackButton />
      </div>

      <div className="mb-8 text-center md:mt-10">
        <span className="mx-auto mb-4 grid size-16 place-items-center rounded-[18px] bg-accent text-white shadow-lg shadow-accent/30">
          <Clapperboard className="size-8" />
        </span>
        <p className="text-[13px] font-semibold tracking-[0.2em] text-accent">WATCHGUIDE PRO</p>
        <h1 className="large-title mt-1">Everything, unlimited.</h1>
        {trialDays > 0 && !pro.isPro && <p className="mt-2 text-[17px] text-muted">{trialDays} days free, then {annualPrice}/year</p>}
      </div>

      <ul className="overflow-hidden rounded-[22px] bg-surface">
        {BENEFITS.map(({ icon: Icon, title, detail }, i) => (
          <li key={title} className="flex items-center gap-4 pl-4">
            <Icon className="size-6 shrink-0 text-tint" />
            <div className={`min-w-0 flex-1 py-3 pr-4 ${i ? "border-t border-line" : ""}`}>
              <p className="text-[17px] font-medium">{title}</p>
              <p className="text-[15px] text-muted">{detail}</p>
            </div>
          </li>
        ))}
      </ul>

      {pro.isPro ? (
        <div className="mt-8 rounded-[22px] bg-surface p-5 text-center">
          <span className="mx-auto mb-3 grid size-12 place-items-center rounded-full bg-[#30d158] text-white"><Check className="size-7" strokeWidth={3} /></span>
          <p className="text-[20px] font-semibold">You have WatchGuide Pro</p>
          {pro.expires && (
            <p className="mt-1 text-[15px] text-muted">
              {pro.willRenew ? "Renews" : "Ends"} {pro.expires.toLocaleDateString(undefined, { day: "numeric", month: "long", year: "numeric" })}
            </p>
          )}
          {pro.managementURL && (
            <a href={pro.managementURL} target="_blank" rel="noreferrer" className="mt-4 inline-block text-[17px] font-medium text-tint">Manage subscription</a>
          )}
        </div>
      ) : pro.status === "unavailable" ? (
        <p className="mt-8 rounded-[22px] bg-surface p-5 text-center text-[15px] text-muted">
          Pro isn&apos;t on sale on the web yet. You can get it in the WatchGuide app for iPhone and iPad.
        </p>
      ) : (
        <>
          <div className="mt-8 space-y-3" role="radiogroup" aria-label="Plan">
            {!plans && !loadError && [0, 1].map((i) => <div key={i} className="skeleton h-[78px] rounded-[18px]" />)}
            {loadError && <p className="text-center text-[15px] text-red-400">{loadError}</p>}
            {annual && (
              <PlanRow
                on={selected === "annual"}
                onSelect={() => setSelected("annual")}
                title="Annual"
                sub={annual ? `Just ${money(annual.amount / 12, annual.currency)}/month, billed yearly` : "per year"}
                price={annualPrice ?? ""}
                badge={savings ? `SAVE ${savings}%` : null}
              />
            )}
            {monthly && (
              <PlanRow on={selected === "monthly"} onSelect={() => setSelected("monthly")} title="Monthly" sub="per month" price={monthlyPrice ?? ""} />
            )}
          </div>

          <button
            type="button"
            onClick={purchase}
            disabled={!plan || busy}
            className="press mt-6 flex h-[60px] w-full items-center justify-center gap-2 rounded-full bg-accent text-[19px] font-semibold text-white disabled:opacity-50"
          >
            {busy && <Loader2 className="size-5 animate-spin" />}
            {showsTrial ? `Start ${trialDays}-day free trial` : plan ? `Continue — ${plan.formatted}/${selected === "annual" ? "year" : "month"}` : "Continue"}
          </button>
          <p className="mt-2 text-center text-[13px] text-muted">
            {showsTrial ? `Free for ${trialDays} days, then ${annualPrice}/year. ` : plan ? `${plan.formatted}/${selected === "annual" ? "year" : "month"}. ` : ""}
            Cancel anytime. Web prices are 15% lower than in the app.
          </p>
          {message && <p className="mt-4 text-center text-[15px]" role="status">{message}</p>}
          {pro.sandbox && <p className="mt-3 text-center text-[13px] font-semibold text-accent">Test mode: no real charge.</p>}

          <p className="mt-6 text-center text-[12px] leading-relaxed text-faint">
            Subscriptions renew automatically until cancelled. Cancel any time from the link in your receipt email or here once subscribed.
            Pro bought on the web works in this browser; to use it in the iOS app too, sign-in is coming.
          </p>
        </>
      )}

      <p className="mt-4 text-center text-[13px]">
        <a href="https://www.watchguide.app/#/privacy" target="_blank" rel="noreferrer" className="text-faint hover:text-text">Privacy Policy</a>
      </p>
    </div>
  );
}

function PlanRow({ on, onSelect, title, sub, price, badge }: { on: boolean; onSelect: () => void; title: string; sub: string; price: string; badge?: string | null }) {
  return (
    <button
      type="button"
      role="radio"
      aria-checked={on}
      onClick={onSelect}
      className={`press flex w-full items-center gap-4 rounded-[18px] bg-surface px-4 py-4 text-left ring-2 transition ${on ? "ring-tint" : "ring-transparent"}`}
    >
      <span className={`grid size-6 shrink-0 place-items-center rounded-full ring-2 ${on ? "bg-tint ring-tint" : "ring-faint"}`}>
        {on && <span className="size-2.5 rounded-full bg-white" />}
      </span>
      <span className="min-w-0 flex-1">
        <span className="flex items-center gap-2 text-[19px] font-semibold">
          {title}
          {badge && <span className="rounded-md bg-[#30d158]/20 px-1.5 py-0.5 text-[12px] font-bold text-[#30d158]">{badge}</span>}
        </span>
        <span className="block text-[15px] text-muted">{sub}</span>
      </span>
      <span className="text-[19px] font-semibold">{price}</span>
    </button>
  );
}
