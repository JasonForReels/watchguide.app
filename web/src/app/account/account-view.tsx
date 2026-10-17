"use client";

import Link from "next/link";
import { Check, LogOut } from "lucide-react";
import { AccountForm } from "@/components/account-form";
import { PageHeader } from "@/components/rail";
import { useAuth } from "@/lib/auth";
import { signOut, usePro } from "@/lib/purchases";

/**
 * WatchGuide is free to use, so an account is optional. It only matters for Pro, which belongs
 * to the account and so works in the iPhone app and on the web.
 */
export function AccountView() {
  const { user, enabled } = useAuth();
  const pro = usePro();

  return (
    <div className="pb-10">
      <PageHeader title="Account" subtitle="Optional. WatchGuide is free to use without one." />
      <div className="mx-auto max-w-xl px-4 sm:px-8">
        {!enabled ? (
          <p className="rounded-[22px] bg-surface p-5 text-center text-[15px] text-muted">Accounts aren&apos;t available on this site yet.</p>
        ) : user ? (
          <div className="space-y-4">
            <div className="rounded-[22px] bg-surface p-5">
              <p className="text-[13px] text-muted">Signed in as</p>
              <p className="break-all text-[19px] font-semibold">{user.email}</p>
              <p className="mt-3 flex items-center gap-2 text-[15px]">
                {pro.isPro ? (
                  <>
                    <span className="grid size-5 place-items-center rounded-full bg-[#30d158] text-white"><Check className="size-3.5" strokeWidth={3} /></span>
                    WatchGuide Pro is on
                    {pro.expires && <span className="text-muted">· {pro.willRenew ? "renews" : "ends"} {pro.expires.toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" })}</span>}
                  </>
                ) : (
                  <span className="text-muted">Free plan · <Link href="/pro" className="font-medium text-tint">Get Pro</Link></span>
                )}
              </p>
              {pro.managementURL && (
                <a href={pro.managementURL} target="_blank" rel="noreferrer" className="mt-3 inline-block text-[15px] font-medium text-tint">Manage subscription</a>
              )}
            </div>
            <p className="px-2 text-[13px] text-muted">
              Sign in with the same account in the WatchGuide app on iPhone and iPad, and Pro works on both.
            </p>
            <button
              type="button"
              onClick={signOut}
              className="press flex h-12 w-full items-center justify-center gap-2 rounded-full bg-surface text-[17px] font-medium text-red-400"
            >
              <LogOut className="size-5" /> Sign out
            </button>
          </div>
        ) : (
          <AccountForm reason="Sign in with your WatchGuide account, the same one as the app. You only need one for Pro." />
        )}
      </div>
    </div>
  );
}
