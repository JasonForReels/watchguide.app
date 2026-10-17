import type { Metadata } from "next";
import { WifiOff } from "lucide-react";

export const metadata: Metadata = { title: "Offline" };

export default function OfflinePage() {
  return (
    <div className="grid min-h-[70dvh] place-items-center px-6 text-center">
      <div>
        <span className="mx-auto mb-4 grid size-14 place-items-center rounded-2xl bg-accent/15 text-accent">
          <WifiOff className="size-7" />
        </span>
        <h1 className="font-display text-2xl font-semibold">You’re offline</h1>
        <p className="mt-2 text-muted">Your lists are saved on this device. Reconnect to browse and search.</p>
        <a href="/lists" className="mt-6 inline-block rounded-full bg-accent px-5 py-2.5 font-medium text-on-accent">Open my lists</a>
      </div>
    </div>
  );
}
