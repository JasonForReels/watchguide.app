import type { Metadata } from "next";
import { StreamQView } from "./streamq-view";

export const metadata: Metadata = { title: "StreamQ", description: "What's on the services you already pay for." };

export default function StreamQPage() {
  return <StreamQView />;
}
