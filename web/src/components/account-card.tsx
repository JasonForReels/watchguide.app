"use client";

import Link from "next/link";
import { useState } from "react";
import { Check, ChevronDown, UserRound } from "lucide-react";
import { AccountForm } from "@/components/account-form";
import { useAuth } from "@/lib/auth";
import { signOut, usePro } from "@/lib/purchases";

/**
 * Sign in or sign up, on the More tab. It is the same account as the iPhone app: it is what
 * lets your lists, StreamQ and picks follow you between devices, and what Pro belongs to.
 */
export function AccountCard({ className = "" }: { className?: string }) {
  const { user, enabled } = useAuth();
  const pro = usePro();
  const [open, setOpen] = useState(false);

  if (!enabled) return null;

  if (user) {
    return (
      <div className={`rounded-[22px] bg-surface p-4 ${className}`}>
        <div className="flex items-center gap-3">
          <span className="grid size-10 shrink-0 place-items-center rounded-full bg-tint/15 text-tint"><UserRound className="size-5" /></span>
          <div className="min-w-0 flex-1">
            <p className="truncate text-[17px] font-semibold">{user.email}</p>
            <p className="flex items-center gap-1.5 text-[13px] text-muted">
              {pro.isPro ? (
                <>
                  <span className="grid size-4 place-items-center rounded-full bg-[#30d158] text-white"><Check className="size-3" strokeWidth={3} /></span>
                  WatchGuide Pro is on
                  {pro.expires && <span>· {pro.willRenew ? "renews" : "ends"} {pro.expires.toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" })}</span>}
                </>
              ) : (
                <>Free plan · <Link href="/pro" className="font-medium text-tint">Get Pro</Link></>
              )}
            </p>
          </div>
        </div>
        <div className="mt-3 flex items-center justify-between border-t border-line pt-3 text-[15px]">
          {pro.managementURL ? (
            <a href={pro.managementURL} target="_blank" rel="noreferrer" className="font-medium text-tint">Manage subscription</a>
          ) : (
            <span className="text-muted">Signed in with the same account as the app</span>
          )}
          <button type="button" onClick={signOut} className="font-medium text-red-400">Sign out</button>
        </div>
      </div>
    );
  }

  return (
    <div className={`overflow-hidden rounded-[22px] bg-surface ${className}`}>
      <button type="button" onClick={() => setOpen(!open)} aria-expanded={open} className="flex w-full items-center gap-3 p-4 text-left">
        <span className="grid size-10 shrink-0 place-items-center rounded-full bg-tint/15 text-tint"><UserRound className="size-5" /></span>
        <span className="min-w-0 flex-1">
          <span className="block text-[17px] font-semibold">Sign in or create an account</span>
          <span className="block text-[13px] text-muted">Keep your lists, StreamQ and picks on every device, and use Pro anywhere.</span>
        </span>
        <ChevronDown className={`size-5 shrink-0 text-faint transition ${open ? "rotate-180" : ""}`} />
      </button>
      {open && (
        <div className="px-4 pb-4">
          <AccountForm reason="Use the same account as the WatchGuide app, so your lists, StreamQ, picks and Pro are the same on both." bare />
        </div>
      )}
    </div>
  );
}
