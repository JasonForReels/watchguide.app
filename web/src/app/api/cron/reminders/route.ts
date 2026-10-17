import webpush from "web-push";
import { allDevices, removeDevice } from "@/lib/push-store";
import { tmdbSafe } from "@/lib/tmdb";
import type { TitleDetails } from "@/lib/types";

/**
 * Daily Vercel Cron: finds followed shows with an episode airing today and followed films
 * releasing today (UTC date), then pushes one notification per device per title.
 * Vercel sends `Authorization: Bearer $CRON_SECRET`. `?date=YYYY-MM-DD` overrides "today" for testing.
 */
interface Hit { title: string; body: string; url: string; tag: string }

async function checkTitle(key: string, today: string): Promise<Hit | null> {
  const [type, idText] = key.split("-");
  const id = Number(idText);
  if (type === "movie") {
    const m = await tmdbSafe<TitleDetails>(`movie/${id}`);
    if (!m || m.release_date !== today) return null;
    return { title: m.title ?? "A film you saved", body: "Releases today.", url: `/title/movie/${id}`, tag: key };
  }
  const t = await tmdbSafe<TitleDetails>(`tv/${id}`);
  const ep = [t?.next_episode_to_air, t?.last_episode_to_air].find((e) => e?.air_date === today);
  if (!t || !ep) return null;
  const label = `S${ep.season_number}E${ep.episode_number}`;
  return { title: t.name ?? "A show you follow", body: `${label}${ep.name ? ` “${ep.name}”` : ""} airs today.`, url: `/title/tv/${id}`, tag: `${key}-${label}` };
}

export async function GET(request: Request) {
  const secret = process.env.CRON_SECRET;
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) {
    return Response.json({ error: "Unauthorized." }, { status: 401 });
  }
  const { VAPID_PUBLIC_KEY, NEXT_PUBLIC_VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT } = process.env;
  const publicKey = NEXT_PUBLIC_VAPID_PUBLIC_KEY ?? VAPID_PUBLIC_KEY;
  if (!publicKey || !VAPID_PRIVATE_KEY || !VAPID_SUBJECT) {
    return Response.json({ error: "VAPID keys are not configured." }, { status: 500 });
  }
  webpush.setVapidDetails(VAPID_SUBJECT, publicKey, VAPID_PRIVATE_KEY);

  const override = new URL(request.url).searchParams.get("date");
  const today = override && /^\d{4}-\d{2}-\d{2}$/.test(override) ? override : new Date().toISOString().slice(0, 10);

  const devices = await allDevices();
  const keys = [...new Set(devices.flatMap((d) => d.ids))];
  const hits = new Map<string, Hit>();
  // Small batches keep us polite to TMDB and inside the function time limit.
  for (let i = 0; i < keys.length; i += 10) {
    await Promise.all(keys.slice(i, i + 10).map(async (k) => {
      const hit = await checkTitle(k, today);
      if (hit) hits.set(k, hit);
    }));
  }

  let sent = 0, removed = 0, failed = 0;
  await Promise.all(devices.map(async (d) => {
    for (const key of d.ids) {
      const hit = hits.get(key);
      if (!hit) continue;
      try {
        await webpush.sendNotification(d.sub, JSON.stringify(hit), { TTL: 60 * 60 * 12 });
        sent++;
      } catch (e) {
        const status = (e as { statusCode?: number }).statusCode;
        if (status === 404 || status === 410) {
          await removeDevice(d.sub.endpoint);
          removed++;
          return;
        }
        failed++;
      }
    }
  }));

  return Response.json({ date: today, devices: devices.length, titlesChecked: keys.length, matches: hits.size, sent, removed, failed });
}
