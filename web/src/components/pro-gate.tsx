"use client";

import Link from "next/link";
import { Lock, Sparkles } from "lucide-react";
import { usePro } from "@/lib/purchases";

/**
 * Shows a Pro feature blurred behind an upgrade card for free users ("Available with
 * WatchGuide Pro" on iOS). Pro users, and sites without purchases set up, see it as is.
 */
export function ProGate({ feature, children }: { feature: string; children: React.ReactNode }) {
  const pro = usePro();
  const locked = pro.status === "free";
  if (!locked) return <>{children}</>;
  return (
    <div className="relative">
      <div aria-hidden inert className="pointer-events-none max-h-[70vh] overflow-hidden blur-md select-none [mask-image:linear-gradient(to_bottom,black_40%,transparent)]">
        {children}
      </div>
      <div className="absolute inset-x-4 top-12 mx-auto max-w-sm rounded-[22px] bg-surface p-6 text-center shadow-2xl ring-1 ring-line">
        <span className="mx-auto mb-3 grid size-12 place-items-center rounded-full bg-accent/15 text-accent"><Lock className="size-6" /></span>
        <p className="text-[20px] font-semibold">{feature}</p>
        <p className="mt-1 text-[15px] text-muted">Available with WatchGuide Pro</p>
        <Link href="/pro" className="press mt-5 inline-block rounded-full bg-accent px-6 py-3 text-[17px] font-semibold text-white">Get Pro</Link>
      </div>
    </div>
  );
}

/** The Pro row at the top of More and Settings: an upsell for free users, status for Pro. */
export function ProCard({ className = "" }: { className?: string }) {
  const pro = usePro();
  if (pro.status === "unavailable") return null;
  return (
    <Link
      href="/pro"
      className={`press flex items-center gap-4 rounded-[22px] bg-gradient-to-br from-accent/25 via-surface to-surface p-4 ring-1 ring-accent/25 ${className}`}
    >
      <span className="grid size-12 shrink-0 place-items-center rounded-[14px] bg-accent text-white shadow-lg shadow-accent/30">
        <Sparkles className="size-6" />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[17px] font-semibold">WatchGuide Pro</span>
        <span className="block text-[13px] text-muted">
          {pro.isPro ? "Active. Thanks for supporting WatchGuide." : "Unlimited Atlas, unlimited lists, stats and more"}
        </span>
      </span>
      <span className={`shrink-0 rounded-full px-3.5 py-1.5 text-[15px] font-semibold ${pro.isPro ? "bg-[#30d158]/20 text-[#30d158]" : "bg-accent text-white"}`}>
        {pro.isPro ? "Active" : "Get Pro"}
      </span>
    </Link>
  );
}
