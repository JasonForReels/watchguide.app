import type { Metadata } from "next";
import { AtlasChat } from "./chat";

export const metadata: Metadata = { title: "Atlas", description: "Ask Atlas, your movie and TV guide." };

export default function AtlasPage() {
  return <AtlasChat />;
}
