// Monthly "leaving soon" lists for the app's Leaving Soon section.
//
// For each streaming service and country below, asks Poe's gpt-5.4-nano with web
// search (same bot and API as Reelmeter's box office updater) what is leaving in the
// next 90 days. When Poe fails or finds nothing, MOTN's /changes endpoint is the
// backup (expiring titles with TMDB ids, 30 days ahead at most). The answer goes
// into Supabase's api_cache under the key the app reads
// (`leaving:catalog:<providerId>:<country>`). The app then only falls back to its
// own Poe search for countries this job doesn't cover.
//
// Runs daily from GitHub Actions, but only refreshes lists older than REFRESH_DAYS,
// up to MAX_CALLS per run, so each list is refreshed about once a month and a run
// never spends more than a day's Poe points.
//
// Needs POE_API_KEY, SUPABASE_URL, SUPABASE_ANON_KEY; MOTN_API_KEY is optional.
// Flags: --dry-run (print, don't write), --only=8:us,384:gb (just these pairs), --force.
//
// The prompt mirrors LeavingDateResearcher.swift; keep the two in sync.

const REFRESH_DAYS = 28;
const LOOKAHEAD_DAYS = 90;
const TTL_SECONDS = 35 * 86400;
// The bot sometimes misses a list that exists, so empty answers are retried after a week.
const EMPTY_TTL_SECONDS = 7 * 86400;
const MAX_CALLS = Number(process.env.MAX_CALLS || 40);
// Leaves this many points for the app's own Poe features.
const MIN_BALANCE = Number(process.env.MIN_BALANCE || 2500);
const BOT = "gpt-5.4-nano";
// MOTN rejects `to` more than 31 days ahead.
const MOTN_DAYS = 30;
const MOTN_PAGES = 5;

// TMDB provider ids and names, as in StreamingService.allServices.
const SERVICES = {
  8: "Netflix", 337: "Disney+", 384: "Max", 15: "Hulu", 531: "Paramount+", 386: "Peacock",
  350: "Apple TV", 283: "Crunchyroll", 73: "Tubi", 300: "Pluto TV", 43: "Starz",
  55: "Showmax", 11: "MUBI", 99: "Shudder", 151: "BritBox",
};

const MAJOR = ["us", "gb", "ca", "au", "ie", "nz", "de", "fr", "es", "it", "nl", "se", "br", "mx", "in", "jp", "kr", "za"];
// Where each service runs, limited to the countries above.
const REGIONS = {
  8: MAJOR,
  337: MAJOR,
  384: ["us", "gb", "ie", "de", "it", "fr", "es", "nl", "se", "au", "br", "mx"],
  15: ["us"],
  531: ["us", "gb", "ie", "ca", "au", "de", "fr", "it", "br", "mx", "kr"],
  386: ["us"],
  350: MAJOR,
  283: MAJOR,
  73: ["us", "ca", "au", "nz", "gb", "mx"],
  300: ["us", "gb", "de", "fr", "es", "it", "br", "mx", "ca"],
  43: ["us"],
  55: ["za"],
  11: MAJOR,
  99: ["us", "gb", "ie", "ca", "au", "nz"],
  151: ["us", "ca", "au", "za", "se"],
};

// TMDB provider id → MOTN service id, as in StreamingDeepLinkService.tmdbToMOTN.
const MOTN_IDS = {
  8: "netflix", 337: "disney", 384: "hbo", 15: "hulu", 531: "paramount", 386: "peacock",
  350: "apple", 283: "crunchyroll", 73: "tubi", 300: "plutotv", 43: "starz",
  55: "showmax", 11: "mubi", 99: "shudder", 151: "britbox",
};
// A rental or purchase "expiring" is noise; only count ways to stream it.
const STREAMABLE = new Set(["subscription", "free", "addon"]);

const REGION_NAMES = {
  us: "United States", gb: "United Kingdom", ca: "Canada", au: "Australia", ie: "Ireland",
  nz: "New Zealand", de: "Germany", fr: "France", es: "Spain", it: "Italy", nl: "Netherlands",
  se: "Sweden", br: "Brazil", mx: "Mexico", in: "India", jp: "Japan", kr: "South Korea", za: "South Africa",
};

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const day = (d) => d.toISOString().slice(0, 10);
// Swift's .iso8601 decoder rejects fractional seconds.
const iso = (d) => d.toISOString().replace(/\.\d{3}Z$/, "Z");

// MARK: - Prompt (mirrors LeavingDateResearcher.swift)

function monthDates(start, end) {
  const dates = [];
  let cursor = new Date(Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), 1));
  while (cursor <= end) {
    dates.push(cursor);
    cursor = new Date(Date.UTC(cursor.getUTCFullYear(), cursor.getUTCMonth() + 1, 1));
  }
  return dates;
}

const monthName = (d) => d.toLocaleString("en-US", { month: "long", year: "numeric", timeZone: "UTC" });

function leavingPages(providerId, country, start, end) {
  const pages = [];
  const slugs = { 8: "netflix", 384: "max", 15: "hulu", 386: "peacock" };
  if (country === "us" && slugs[providerId]) {
    for (const d of monthDates(start, end)) {
      const month = d.toLocaleString("en-US", { month: "long", timeZone: "UTC" }).toLowerCase();
      pages.push(`https://leavingsoon.com/${slugs[providerId]}/archive/${d.getUTCFullYear()}/${month}`);
    }
  }
  if (providerId === 8 && ["us", "gb", "ca", "jp", "kr"].includes(country)) {
    pages.push(`https://netflix-soon.pages.dev/${country}/`);
  }
  return pages;
}

function prompt(providerId, country, now, until) {
  const service = SERVICES[providerId];
  const name = providerId === 384 ? "HBO Max" : service;
  const regionName = REGION_NAMES[country] ?? country.toUpperCase();
  const today = day(now);
  const end = day(until);
  const isUS = country === "us";
  const place = isUS ? "" : ` ${regionName}`;
  const searches = monthDates(now, until).map((d) => `"leaving ${name}${place} ${monthName(d)}"`).join(", ");
  const sources = (isUS ? "leavingsoon.com, " : "") + "What's on Netflix, JustWatch, Decider, Tom's Guide";
  const pages = leavingPages(providerId, country, now, until);
  const pageLine = pages.length ? `Open these pages first and read every date on them: ${pages.join(" ")}.\n` : "";

  const instructions =
    "You are a streaming catalog data extractor. Search the web and report only titles with a " +
    "specific last day stated on the page. Never estimate or guess. " +
    "Respond with a single JSON object and nothing else.";
  const input = `Today is ${today}. List every movie and TV show scheduled to leave ${name} in ${regionName} between ${today} and ${end}.
${pageLine}Also search ${searches}. Good sources: ${sources}, ${name}'s own announcements for ${regionName}.
${isUS ? "" : `Only use lists specifically for ${regionName}. Catalogs differ by country: US lists, including Netflix's Tudum article, are wrong for ${regionName}.`}
An empty list is fine.

Return exactly this JSON shape:
{"leaving":[{"title":"Inception","year":2010,"date":"2026-11-01"}]}
"title" is the title only, without season info. "year" is the release year, or null if unknown. "date" is the last day it is available, as YYYY-MM-DD.`;
  return { instructions, input };
}

// MARK: - Poe

async function poe(path, init, key) {
  for (let n = 0; ; n++) {
    let r;
    try {
      r = await fetch("https://api.poe.com" + path, {
        ...init,
        headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
        signal: AbortSignal.timeout(180e3),
      });
    } catch (e) {
      if (n < 2) { await sleep(2000 * 3 ** n); continue; }
      throw new Error(`network: ${e.message}`);
    }
    if ((r.status === 429 || r.status >= 500) && n < 2) { await sleep(2000 * 3 ** n); continue; }
    const text = await r.text();
    if (!r.ok) throw new Error(`HTTP ${r.status}: ${text.slice(0, 300)}`);
    return JSON.parse(text);
  }
}

async function balance(key) {
  try {
    return (await poe("/usage/current_balance", { method: "GET" }, key)).current_point_balance ?? null;
  } catch {
    return null;
  }
}

function responsesText(json) {
  if (typeof json.output_text === "string") return json.output_text;
  return (json.output || [])
    .filter((o) => o.type === "message")
    .flatMap((o) => o.content || [])
    .filter((c) => c.type === "output_text")
    .map((c) => c.text)
    .join("\n");
}

/** The parsed leaving list, or null when the reply isn't usable (nothing is cached then). */
function parse(text, now, until) {
  const s = (text || "").replace(/```(?:json)?/gi, "");
  const start = s.indexOf("{");
  const end = s.lastIndexOf("}");
  if (start < 0 || end < start) return null;
  let rows;
  try {
    rows = JSON.parse(s.slice(start, end + 1)).leaving;
  } catch {
    return null;
  }
  if (!Array.isArray(rows)) return null;

  const seen = new Set();
  const listings = [];
  for (const row of rows) {
    const title = typeof row?.title === "string" ? row.title.trim() : "";
    const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(row?.date ?? ""));
    if (!title || !m) continue;
    // The listed date is the last day available — treat it as end of day.
    const date = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3], 23, 59));
    if (date <= now || date > new Date(until.getTime() + 86400e3)) continue;
    const year = Number.isInteger(row.year) ? row.year : null;
    const id = `${title.toLowerCase()}|${year}|${day(date)}`;
    if (seen.has(id)) continue;
    seen.add(id);
    listings.push({ title, year, date: iso(date) });
  }
  return listings.sort((a, b) => a.date.localeCompare(b.date));
}

// MARK: - MOTN

/** Titles MOTN says leave the service in the next MOTN_DAYS, or null if the request failed. */
async function motn(providerId, country, key) {
  const service = MOTN_IDS[providerId];
  if (!key || !service) return null;
  const now = new Date();
  const from = Math.floor(now.getTime() / 1000);
  const to = from + MOTN_DAYS * 86400;
  const listings = [];
  let cursor;
  for (let page = 0; page < MOTN_PAGES; page++) {
    const params = new URLSearchParams({
      change_type: "expiring", item_type: "show", country, catalogs: service,
      from: String(from), to: String(to), output_language: "en",
    });
    if (cursor) params.set("cursor", cursor);
    let json;
    try {
      const r = await fetch(`https://api.movieofthenight.com/v4/changes?${params}`, {
        headers: { "X-API-Key": key },
        signal: AbortSignal.timeout(30e3),
      });
      if (!r.ok) {
        console.log(`    MOTN HTTP ${r.status}: ${(await r.text()).slice(0, 200)}`);
        return page ? listings : null;
      }
      json = await r.json();
    } catch (e) {
      console.log(`    MOTN ${e.message}`);
      return page ? listings : null;
    }
    const shows = json.shows || {};
    for (const change of json.changes || []) {
      if (change.streamingOptionType && !STREAMABLE.has(change.streamingOptionType)) continue;
      const show = shows[change.showId] || {};
      if (!show.title || !change.timestamp) continue;
      const date = new Date(change.timestamp * 1000);
      if (date <= now) continue;
      // "movie/550" or "tv/1399"
      const [type, id] = String(show.tmdbId || "").split("/");
      listings.push({
        title: show.title,
        year: show.releaseYear ?? show.firstAirYear ?? null,
        date: iso(date),
        tmdbId: Number(id) || null,
        type: type === "movie" || type === "tv" ? type : null,
      });
    }
    if (!json.hasMore || !json.nextCursor) break;
    cursor = json.nextCursor;
  }
  return listings;
}

const normalize = (t) =>
  t.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/&/g, "and")
    .replace(/[^a-z0-9 ]/g, "").replace(/^(the|a|an) /, "").replace(/ /g, "");

/** One entry per title (MOTN lists a title once per streaming option), earliest date. */
function dedupe(listings) {
  const byTitle = new Map();
  for (const l of listings) {
    const k = normalize(l.title);
    const existing = byTitle.get(k);
    if (!existing || l.date < existing.date) byTitle.set(k, l);
  }
  return [...byTitle.values()].sort((a, b) => a.date.localeCompare(b.date));
}

// MARK: - Supabase api_cache

function supabase() {
  const url = (process.env.SUPABASE_URL || "").replace(/\/$/, "");
  const key = process.env.SUPABASE_ANON_KEY || "";
  const headers = { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" };
  return {
    /** cache_key → created_at for this job's own unexpired entries (the app's own writes have shorter TTLs). */
    async fresh() {
      const q = `cache_key=like.leaving:catalog:*&expires_at=gt.${iso(new Date())}&ttl_seconds=gte.${EMPTY_TTL_SECONDS}&select=cache_key,created_at`;
      const r = await fetch(`${url}/rest/v1/api_cache?${q}`, { headers });
      if (!r.ok) throw new Error(`Supabase read HTTP ${r.status}: ${(await r.text()).slice(0, 200)}`);
      return new Map((await r.json()).map((row) => [row.cache_key, new Date(row.created_at)]));
    },
    async write(cacheKey, listings, complete) {
      const now = new Date();
      // An empty list, or one only MOTN could answer, is retried after a week.
      const ttl = listings.length && complete ? TTL_SECONDS : EMPTY_TTL_SECONDS;
      const body = {
        cache_key: cacheKey,
        source: "deeplink",
        response_data: { listings },
        ttl_seconds: ttl,
        created_at: iso(now),
        expires_at: iso(new Date(now.getTime() + ttl * 1000)),
        hit_count: 0,
      };
      const r = await fetch(`${url}/rest/v1/api_cache`, {
        method: "POST",
        headers: { ...headers, Prefer: "resolution=merge-duplicates" },
        body: JSON.stringify(body),
      });
      if (!r.ok) throw new Error(`Supabase write HTTP ${r.status}: ${(await r.text()).slice(0, 200)}`);
    },
  };
}

// MARK: - Main

async function main() {
  const args = process.argv.slice(2);
  const dryRun = args.includes("--dry-run");
  const force = args.includes("--force");
  const only = args.find((a) => a.startsWith("--only="))?.slice(7).split(",").map((p) => p.split(":"));

  const key = process.env.POE_API_KEY;
  if (!key) throw new Error("POE_API_KEY is missing.");
  const db = supabase();
  if (!dryRun && !(process.env.SUPABASE_URL && process.env.SUPABASE_ANON_KEY)) {
    throw new Error("SUPABASE_URL and SUPABASE_ANON_KEY are missing.");
  }

  let pairs = only
    ? only.map(([id, cc]) => [Number(id), cc.toLowerCase()])
    : Object.entries(REGIONS).flatMap(([id, ccs]) => [...new Set(ccs)].map((cc) => [Number(id), cc]));

  // Oldest lists first; skip ones refreshed within REFRESH_DAYS.
  const fresh = dryRun ? new Map() : await db.fresh();
  const cutoff = Date.now() - REFRESH_DAYS * 86400e3;
  const age = ([id, cc]) => fresh.get(`leaving:catalog:${id}:${cc}`)?.getTime() ?? 0;
  if (!force) pairs = pairs.filter((p) => age(p) < cutoff);
  pairs.sort((a, b) => age(a) - age(b));

  console.log(`[1/2] ${pairs.length} lists due; doing up to ${MAX_CALLS} this run.`);
  let calls = 0, written = 0, failed = 0;
  for (const [providerId, country] of pairs) {
    if (calls >= MAX_CALLS) break;
    const before = await balance(key);
    if (before != null && before < MIN_BALANCE) {
      console.log(`Stopping: ${before} points left (keeping ${MIN_BALANCE} for the app).`);
      break;
    }
    calls++;
    const now = new Date();
    const until = new Date(now.getTime() + LOOKAHEAD_DAYS * 86400e3);
    const label = `${SERVICES[providerId]} ${country.toUpperCase()}`;
    try {
      let poeListings = null;
      try {
        const { instructions, input } = prompt(providerId, country, now, until);
        const json = await poe("/v1/responses", {
          method: "POST",
          body: JSON.stringify({ model: BOT, instructions, input, tools: [{ type: "web_search_preview" }] }),
        }, key);
        poeListings = parse(responsesText(json), now, until);
      } catch (e) {
        console.log(`    Poe ${e.message}`);
      }
      const after = await balance(key);
      const points = before != null && after != null ? before - after : "?";

      // MOTN is the backup when Poe fails or finds nothing.
      const motnListings = poeListings?.length ? null : await motn(providerId, country, process.env.MOTN_API_KEY);
      const listings = poeListings?.length ? poeListings : motnListings?.length ? dedupe(motnListings) : poeListings ?? motnListings;
      if (!listings) {
        failed++;
        console.log(`  ${label}: no usable answer from Poe or MOTN, not cached (${points} pts)`);
        continue;
      }
      const source = poeListings?.length ? "Poe" : motnListings?.length ? "MOTN backup" : "both empty";
      if (!dryRun) await db.write(`leaving:catalog:${providerId}:${country}`, listings, source === "Poe");
      written++;
      console.log(`  ${label}: ${listings.length} titles (${source}; ${points} pts)${dryRun ? " [dry run]" : ""}`);
    } catch (e) {
      failed++;
      console.log(`  ${label}: ${e.message}`);
    }
    await sleep(2000);
  }
  console.log(`[2/2] Done: ${written} written, ${failed} failed, ${Math.max(0, pairs.length - calls)} left for later runs.`);
  if (calls > 0 && written === 0) process.exit(1);
}

main().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
