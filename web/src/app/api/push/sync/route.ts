import { isFollowKey, isPushEndpoint, saveDevice } from "@/lib/push-store";

const MAX_IDS = 400;

/** Stores this device's push subscription and the titles it follows. Called again whenever the lists change. */
export async function POST(request: Request) {
  const text = await request.text();
  if (text.length > 20_000) return Response.json({ error: "Too large." }, { status: 413 });
  let body: { subscription?: { endpoint?: unknown; keys?: { p256dh?: unknown; auth?: unknown } }; ids?: unknown };
  try {
    body = JSON.parse(text);
  } catch {
    return Response.json({ error: "Bad JSON." }, { status: 400 });
  }
  const sub = body.subscription;
  if (!sub || !isPushEndpoint(sub.endpoint) || typeof sub.keys?.p256dh !== "string" || typeof sub.keys.auth !== "string") {
    return Response.json({ error: "Invalid subscription." }, { status: 400 });
  }
  if (!Array.isArray(body.ids)) return Response.json({ error: "ids must be an array." }, { status: 400 });
  const ids = [...new Set(body.ids.filter(isFollowKey))].slice(0, MAX_IDS);
  try {
    await saveDevice({ sub: { endpoint: sub.endpoint, keys: { p256dh: sub.keys.p256dh, auth: sub.keys.auth } }, ids, updatedAt: Date.now() });
  } catch {
    return Response.json({ error: "Storage unavailable." }, { status: 503 });
  }
  return Response.json({ ok: true, count: ids.length });
}
