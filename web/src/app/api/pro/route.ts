/**
 * WatchGuide Pro entitlement, through RevenueCat's Paddle app.
 *
 * The browser pays with Paddle.js; RevenueCat learns about the purchase from Paddle's webhooks
 * and from the receipt POST below, then answers "is this user Pro?". Both calls go through
 * the server so the RevenueCat key stays out of the page and CORS never comes into it.
 */

const API = "https://api.revenuecat.com/v1";
const ENTITLEMENT = "watchguide_pro";
const UID = /^[A-Za-z0-9$_.:-]{8,100}$/;

interface Entitlement { expires_date: string | null; product_identifier: string }
interface Subscription { unsubscribe_detected_at: string | null; billing_issues_detected_at: string | null; is_sandbox?: boolean }
interface Subscriber {
  entitlements: Record<string, Entitlement>;
  subscriptions: Record<string, Subscription>;
  management_url: string | null;
}

function shape(sub: Subscriber) {
  const ent = sub.entitlements?.[ENTITLEMENT];
  const active = !!ent && (ent.expires_date === null || new Date(ent.expires_date) > new Date());
  const s = ent ? sub.subscriptions?.[ent.product_identifier] : undefined;
  return {
    pro: active,
    expires: active ? ent.expires_date : null,
    willRenew: active && !!ent.expires_date && !!s && !s.unsubscribe_detected_at && !s.billing_issues_detected_at,
    managementURL: sub.management_url ?? null,
    sandbox: !!s?.is_sandbox,
  };
}

function headers(key: string): HeadersInit {
  return { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "X-Platform": "paddle" };
}

function notSetUp() {
  return Response.json({ error: "Purchases aren't set up on this server. Add REVENUECAT_PADDLE_API_KEY." }, { status: 503 });
}

/** Current entitlement for an anonymous web user. */
export async function GET(request: Request) {
  const key = process.env.REVENUECAT_PADDLE_API_KEY;
  if (!key) return notSetUp();
  const uid = new URL(request.url).searchParams.get("uid") ?? "";
  if (!UID.test(uid)) return Response.json({ error: "Bad request" }, { status: 400 });

  const res = await fetch(`${API}/subscribers/${encodeURIComponent(uid)}`, { headers: headers(key), cache: "no-store" });
  if (!res.ok) return Response.json({ error: "RevenueCat didn't answer." }, { status: 502 });
  return Response.json(shape(((await res.json()) as { subscriber: Subscriber }).subscriber), { headers: { "Cache-Control": "no-store" } });
}

/** Attaches a finished Paddle transaction to this user, so Pro unlocks without waiting for the webhook. */
export async function POST(request: Request) {
  const key = process.env.REVENUECAT_PADDLE_API_KEY;
  if (!key) return notSetUp();

  let body: { uid?: string; transactionId?: string };
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "Bad request" }, { status: 400 });
  }
  if (!body.uid || !UID.test(body.uid) || !body.transactionId || !/^(txn|sub)_[a-z0-9]+$/.test(body.transactionId)) {
    return Response.json({ error: "Bad request" }, { status: 400 });
  }

  const res = await fetch(`${API}/receipts`, {
    method: "POST",
    headers: headers(key),
    body: JSON.stringify({ app_user_id: body.uid, fetch_token: body.transactionId }),
    cache: "no-store",
  });
  if (!res.ok) return Response.json({ error: "The purchase couldn't be confirmed yet." }, { status: 502 });
  return Response.json(shape(((await res.json()) as { subscriber: Subscriber }).subscriber), { headers: { "Cache-Control": "no-store" } });
}
