import type { Metadata } from "next";
import { ProView } from "./pro-view";

export const metadata: Metadata = { title: "WatchGuide Pro", description: "Unlimited Atlas, unlimited lists, stats and more." };

export default function ProPage() {
  return <ProView />;
}
