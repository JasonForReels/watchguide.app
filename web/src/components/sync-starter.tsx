"use client";

import { useEffect } from "react";
import { startSync } from "@/lib/sync";

/** Starts account sync once per page load. Renders nothing. */
export function SyncStarter() {
  useEffect(() => { startSync(); }, []);
  return null;
}
