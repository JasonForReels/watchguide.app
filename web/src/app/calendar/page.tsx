import type { Metadata } from "next";
import { CalendarView } from "./calendar-view";

export const metadata: Metadata = { title: "Calendar", description: "Countdowns to new episodes and releases." };

export default function CalendarPage() {
  return <CalendarView />;
}
