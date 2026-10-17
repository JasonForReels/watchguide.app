import type { Metadata } from "next";
import { TonightDeck } from "./deck";

export const metadata: Metadata = { title: "Tonight", description: "One title at a time. Swipe to decide what to watch tonight." };

export default function TonightPage() {
  return <TonightDeck />;
}
