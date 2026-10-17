/**
 * WatchGuide Pro entitlement, through RevenueCat's Paddle app.
 *
 * The browser pays with Paddle.js; RevenueCat learns about the purchase from Paddle's webhooks
 * and from the receipt POST below, then answers "is this user Pro?". Both calls go through
 * the server so the RevenueCat key stays out of the page and CORS never comes into it.
 *
 * Who the user is comes from their Supabase access token (the same accounts as the iOS app),
 * checked here against Supabase, never from an ID the browser claims. That Supabase user ID is
 * also the RevenueCat app user ID, so Pro follows the account across web and iPhone.
 */

const API = "https://api.revenuecat.com/v1";
const ENTITLEMENT = "watchguide_pro";
const SUPABASE_URL = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? "").replace(/\/+$/, "");
const SUPABASE_ANON = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";

/** The signed-in user's ID, or null if the token is missing, expired or forged. */
async function userFrom(request: Request): Promise<string | null> {
  const token = request.headers.get("authorization")?.match(/^Bearer (.+)$/)?.[1];
  if (!token || !SUPABASE_URL || !SUPABASE_ANON) return null;
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { Authorization: `Bearer ${token}`, apikey: SUPABASE_ANON },
    cache: "no-store",
  });
  if (!res.ok) return null;
  const id = ((await res.json()) as { id?: string }).id;
  return id && /^[0-9a-f-]{36}$/i.test(id) ? id : null;
}

const signedOut = () => Response.json({ error: "Sign in to continue." }, { status: 401 });

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

/** Current entitlement for the signed-in user. */
export async function GET(request: Request) {
  const key = process.env.REVENUECAT_PADDLE_API_KEY;
  if (!key) return notSetUp();
  const uid = await userFrom(request);
  if (!uid) return signedOut();

  const res = await fetch(`${API}/subscribers/${encodeURIComponent(uid)}`, { headers: headers(key), cache: "no-store" });
  if (!res.ok) return Response.json({ error: "RevenueCat didn't answer." }, { status: 502 });
  return Response.json(shape(((await res.json()) as { subscriber: Subscriber }).subscriber), { headers: { "Cache-Control": "no-store" } });
}

/** Attaches a finished Paddle transaction to this user, so Pro unlocks without waiting for the webhook. */
export async function POST(request: Request) {
  const key = process.env.REVENUECAT_PADDLE_API_KEY;
  if (!key) return notSetUp();

  const uid = await userFrom(request);
  if (!uid) return signedOut();

  let body: { transactionId?: string };
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "Bad request" }, { status: 400 });
  }
  if (!body.transactionId || !/^(txn|sub)_[a-z0-9]+$/.test(body.transactionId)) {
    return Response.json({ error: "Bad request" }, { status: 400 });
  }

  const res = await fetch(`${API}/receipts`, {
    method: "POST",
    headers: headers(key),
    body: JSON.stringify({ app_user_id: uid, fetch_token: body.transactionId }),
    cache: "no-store",
  });
  if (!res.ok) return Response.json({ error: "The purchase couldn't be confirmed yet." }, { status: 502 });
  return Response.json(shape(((await res.json()) as { subscriber: Subscriber }).subscriber), { headers: { "Cache-Control": "no-store" } });
}
