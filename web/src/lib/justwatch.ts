/** Server-only RapidAPI JustWatch client. The key never leaves the server. */
const HOST = process.env.RAPIDAPI_JUSTWATCH_HOST ?? "justwatch9.p.rapidapi.com";

export async function justwatch(path: string, query: Record<string, string> = {}) {
  const key = process.env.RAPIDAPI_KEY;
  if (!key) throw new Error("RAPIDAPI_KEY is not set. Add it to .env.local.");
  const url = new URL(`https://${HOST}/${path}`);
  for (const [k, v] of Object.entries(query)) url.searchParams.set(k, v);
  const res = await fetch(url, {
    headers: { "x-rapidapi-key": key, "x-rapidapi-host": HOST },
    next: { revalidate: 86400 },
  });
  if (!res.ok) throw new Error(`JustWatch ${res.status}`);
  return res.json();
}
