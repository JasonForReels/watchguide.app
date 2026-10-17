import "server-only";
import { createHash } from "node:crypto";

/**
 * Server storage for web push reminders: one record per device, keyed by a hash of its push
 * endpoint (no accounts). Uses Upstash Redis over REST (Vercel Marketplace sets KV_REST_API_URL
 * and KV_REST_API_TOKEN). Without those, local dev falls back to memory; production needs Redis.
 */
export interface PushSubscriptionJSON {
  endpoint: string;
  keys: { p256dh: string; auth: string };
}

export interface DeviceRecord {
  sub: PushSubscriptionJSON;
  /** Followed titles as "tv-123" / "movie-456". */
  ids: string[];
  updatedAt: number;
}

const URL_ = process.env.KV_REST_API_URL ?? process.env.UPSTASH_REDIS_REST_URL;
const TOKEN = process.env.KV_REST_API_TOKEN ?? process.env.UPSTASH_REDIS_REST_TOKEN;
const INDEX = "wg:push:devices";
const prefix = "wg:push:device:";

export const deviceId = (endpoint: string) => createHash("sha256").update(endpoint).digest("hex").slice(0, 32);

type Cmd = (string | number)[];

async function redis(commands: Cmd[]): Promise<unknown[]> {
  if (!URL_ || !TOKEN) throw new Error("Redis is not configured (KV_REST_API_URL / KV_REST_API_TOKEN).");
  const res = await fetch(`${URL_.replace(/\/+$/, "")}/pipeline`, {
    method: "POST",
    headers: { Authorization: `Bearer ${TOKEN}`, "Content-Type": "application/json" },
    body: JSON.stringify(commands),
    cache: "no-store",
  });
  if (!res.ok) throw new Error(`Redis ${res.status}`);
  const out = (await res.json()) as { result?: unknown; error?: string }[];
  const failed = out.find((o) => o.error);
  if (failed) throw new Error(`Redis: ${failed.error}`);
  return out.map((o) => o.result);
}

// Dev-only fallback so the feature can be exercised without a Redis database.
const mem = (globalThis as { __wgPush?: Map<string, string> }).__wgPush ?? new Map<string, string>();
(globalThis as { __wgPush?: Map<string, string> }).__wgPush = mem;
const useMemory = !URL_ || !TOKEN;
if (useMemory && process.env.NODE_ENV === "production") console.warn("[push] Redis env vars missing; reminders will not persist.");

export async function saveDevice(record: DeviceRecord): Promise<void> {
  const id = deviceId(record.sub.endpoint);
  const json = JSON.stringify(record);
  if (useMemory) return void mem.set(id, json);
  await redis([["SET", prefix + id, json], ["SADD", INDEX, id]]);
}

export async function removeDevice(endpoint: string): Promise<void> {
  const id = deviceId(endpoint);
  if (useMemory) return void mem.delete(id);
  await redis([["DEL", prefix + id], ["SREM", INDEX, id]]);
}

export async function allDevices(): Promise<DeviceRecord[]> {
  if (useMemory) return [...mem.values()].map((v) => JSON.parse(v) as DeviceRecord);
  const [members] = await redis([["SMEMBERS", INDEX]]);
  const ids = members as string[];
  if (!ids.length) return [];
  const rows = await redis([["MGET", ...ids.map((i) => prefix + i)]]);
  const out: DeviceRecord[] = [];
  const stale: string[] = [];
  (rows[0] as (string | null)[]).forEach((v, i) => (v ? out.push(JSON.parse(v) as DeviceRecord) : stale.push(ids[i])));
  if (stale.length) await redis([["SREM", INDEX, ...stale]]);
  return out;
}

const PUSH_HOSTS = [
  /(^|\.)fcm\.googleapis\.com$/,
  /(^|\.)push\.services\.mozilla\.com$/,
  /(^|\.)push\.apple\.com$/,
  /(^|\.)notify\.windows\.com$/,
];

/** Accept only real browser push services (never an arbitrary URL the server would then call). */
export function isPushEndpoint(endpoint: unknown): endpoint is string {
  if (typeof endpoint !== "string" || endpoint.length > 1000) return false;
  try {
    const u = new URL(endpoint);
    if (process.env.PUSH_ALLOW_LOCALHOST === "1" && u.hostname === "localhost") return true;
    return u.protocol === "https:" && PUSH_HOSTS.some((r) => r.test(u.hostname));
  } catch {
    return false;
  }
}

export const isFollowKey = (k: unknown): k is string => typeof k === "string" && /^(movie|tv)-\d{1,9}$/.test(k);
