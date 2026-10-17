import type { Metadata } from "next";
import { Suspense } from "react";
import { DiscoverView } from "./discover-view";

export const metadata: Metadata = { title: "Moods", description: "Pick a mood and find something that fits." };

export default function DiscoverPage() {
  return (
    <Suspense>
      <DiscoverView />
    </Suspense>
  );
}
