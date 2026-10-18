import { defineCloudflareConfig } from "@opennextjs/cloudflare";
import kvIncrementalCache from "@opennextjs/cloudflare/overrides/incremental-cache/kv-incremental-cache";

// Caches rendered pages and fetch results in Workers KV so ISR (revalidate) works.
export default defineCloudflareConfig({ incrementalCache: kvIncrementalCache });
