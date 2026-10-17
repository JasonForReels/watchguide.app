import type { Metadata } from "next";
import { Suspense } from "react";
import { ListsView } from "./lists-view";

export const metadata: Metadata = { title: "Lists" };

export default function ListsPage() {
  return (
    <Suspense>
      <ListsView />
    </Suspense>
  );
}
