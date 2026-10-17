"use client";

/**
 * Account sign-in, the same Supabase email + password accounts as the iOS app (AuthService.swift).
 *
 * Talks to Supabase's GoTrue REST endpoints directly (/auth/v1/signup, /auth/v1/token), like the
 * iOS app does, so there is no SDK. The signed-in user's ID is also the RevenueCat app user ID,
 * which is what makes Pro bought on the web show up in the iPhone app and the other way round.
 */

import { useSyncExternalStore } from "react";

const URL_BASE = (process.env.NEXT_PUBLIC_SUPABASE_URL ?? "").replace(/\/+$/, "");
const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? "";
export const AUTH_ENABLED = !!URL_BASE && !!ANON_KEY;

const SESSION_KEY = "watchguide.supabase_session";

export interface AuthUser { id: string; email: string }
interface Session { accessToken: string; refreshToken: string; expiresAt: number; user: AuthUser }

let session: Session | null = null;
let loaded = false;
const listeners = new Set<() => void>();
const emit = () => listeners.forEach((l) => l());

function storage(): Storage | null {
  try { return window.localStorage; } catch { return null; }
}

function load() {
  if (loaded || typeof window === "undefined") return;
  loaded = true;
  try {
    const raw = storage()?.getItem(SESSION_KEY);
    session = raw ? (JSON.parse(raw) as Session) : null;
  } catch {
    session = null;
  }
}

function save(next: Session | null) {
  session = next;
  try {
    if (next) storage()?.setItem(SESSION_KEY, JSON.stringify(next));
    else storage()?.removeItem(SESSION_KEY);
  } catch { /* private mode: the session lasts until the tab closes */ }
  emit();
}

interface GoTrueResponse {
  access_token?: string;
  refresh_token?: string;
  expires_at?: number;
  expires_in?: number;
  user?: { id: string; email?: string };
  msg?: string;
  message?: string;
  error_description?: string;
}

function toSession(r: GoTrueResponse): Session | null {
  if (!r.access_token || !r.refresh_token || !r.user?.id) return null;
  return {
    accessToken: r.access_token,
    refreshToken: r.refresh_token,
    expiresAt: r.expires_at ?? Math.floor(Date.now() / 1000) + (r.expires_in ?? 3600),
    user: { id: r.user.id, email: r.user.email ?? "" },
  };
}

async function call(path: string, body: unknown): Promise<{ ok: boolean; data: GoTrueResponse }> {
  const res = await fetch(`${URL_BASE}/auth/v1/${path}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: ANON_KEY },
    body: JSON.stringify(body),
  });
  const data = (await res.json().catch(() => ({}))) as GoTrueResponse;
  return { ok: res.ok, data };
}

export type AuthResult = { ok: true } | { ok: false; message: string };

export async function signIn(email: string, password: string): Promise<AuthResult> {
  if (!AUTH_ENABLED) return { ok: false, message: "Sign-in isn't set up on this site yet." };
  try {
    const { ok, data } = await call("token?grant_type=password", { email, password });
    const s = ok ? toSession(data) : null;
    if (!s) return { ok: false, message: data.msg ?? data.message ?? data.error_description ?? "Invalid email or password." };
    save(s);
    return { ok: true };
  } catch {
    return { ok: false, message: "Couldn't reach the server. Check your connection." };
  }
}

export async function signUp(email: string, password: string): Promise<AuthResult> {
  if (!AUTH_ENABLED) return { ok: false, message: "Sign-in isn't set up on this site yet." };
  try {
    const { ok, data } = await call("signup", { email, password });
    if (!ok) return { ok: false, message: data.msg ?? data.message ?? "Sign up failed." };
    const s = toSession(data);
    if (!s) return { ok: false, message: "Check your email to confirm your account, then sign in." };
    save(s);
    return { ok: true };
  } catch {
    return { ok: false, message: "Couldn't reach the server. Check your connection." };
  }
}

/** Calls back whenever the signed-in account changes. */
export function onAuthChange(cb: () => void): () => void {
  listeners.add(cb);
  return () => listeners.delete(cb);
}

export function signOut() {
  save(null);
}

/** A valid access token, refreshed when it is about to expire. Null when signed out. */
export async function getAccessToken(): Promise<string | null> {
  load();
  if (!session) return null;
  if (session.expiresAt - 60 > Math.floor(Date.now() / 1000)) return session.accessToken;
  try {
    const { ok, data } = await call("token?grant_type=refresh_token", { refresh_token: session.refreshToken });
    const s = ok ? toSession(data) : null;
    if (!s) { save(null); return null; }
    save(s);
    return s.accessToken;
  } catch {
    return session.accessToken; // offline: let the server decide
  }
}

/** The signed-in user. Signed out until hydrated, so server and first client render agree. */
export function useAuth(): { user: AuthUser | null; enabled: boolean } {
  const user = useSyncExternalStore(
    (l) => { load(); listeners.add(l); return () => listeners.delete(l); },
    () => { load(); return session?.user ?? null; },
    () => null,
  );
  return { user, enabled: AUTH_ENABLED };
}
