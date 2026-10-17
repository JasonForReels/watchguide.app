import type { Metadata } from "next";
import Link from "next/link";
import { Bookmark, CalendarDays, ChevronRight, Clapperboard, Compass, Layers3, MessageCircle, PieChart, Settings } from "lucide-react";
import type { LucideIcon } from "lucide-react";
import { AccountCard } from "@/components/account-card";
import { ProCard } from "@/components/pro-gate";
import { InstallButton } from "@/components/pwa";
import { PageHeader } from "@/components/rail";

export const metadata: Metadata = { title: "More" };

interface Row { href: string; label: string; note: string; icon: LucideIcon; color: string }

/** Grouped like an iOS inset list, with Settings-style coloured icon tiles. */
const GROUPS: Row[][] = [
  [
    { href: "/lists", label: "My Lists", note: "Watchlist, watched, liked and your own", icon: Bookmark, color: "#0a84ff" },
    { href: "/tonight", label: "Tonight", note: "One pick at a time", icon: Clapperboard, color: "#ff9f0a" },
    { href: "/atlas", label: "Ask Atlas", note: "Your AI movie & TV guide", icon: MessageCircle, color: "#bf5af2" },
  ],
  [
    { href: "/discover", label: "Moods", note: "Find something that fits how you feel", icon: Compass, color: "#30d158" },
    { href: "/calendar", label: "Calendar", note: "New episodes and releases", icon: CalendarDays, color: "#ff453a" },
    { href: "/hubs", label: "Hubs", note: "Studios and networks", icon: Layers3, color: "#5e5ce6" },
    { href: "/stats", label: "Your Pulse", note: "Stats from your watching", icon: PieChart, color: "#ff375f" },
  ],
  [
    { href: "/settings", label: "Settings", note: "Themes, region, backup", icon: Settings, color: "#8e8e93" },
  ],
];

export default function MorePage() {
  return (
    <div className="mx-auto max-w-3xl pb-10">
      <PageHeader root title="More" />
      <ProCard className="mx-4 mb-4 sm:mx-8" />
      <AccountCard className="mx-4 mb-7 sm:mx-8" />
      <InstallButton />
      <div className="space-y-7">
        {GROUPS.map((rows, g) => (
          <ul key={g} className="mx-4 overflow-hidden rounded-[22px] bg-surface sm:mx-8">
            {rows.map(({ href, label, note, icon: Icon, color }, i) => (
              <li key={href}>
                <Link href={href} className="flex items-center gap-3.5 pl-4 hover:bg-text/5 active:bg-text/10">
                  <span className="grid size-[30px] shrink-0 place-items-center rounded-[8px] text-white" style={{ background: color }}>
                    <Icon className="size-[18px]" strokeWidth={2.2} />
                  </span>
                  <span className={`flex min-w-0 flex-1 items-center gap-2 py-3 pr-4 ${i ? "border-t border-line" : ""}`}>
                    <span className="min-w-0 flex-1">
                      <span className="block text-[17px]">{label}</span>
                      <span className="block truncate text-[13px] text-muted">{note}</span>
                    </span>
                    <ChevronRight className="size-5 shrink-0 text-faint" strokeWidth={2.4} />
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        ))}
      </div>
    </div>
  );
}
