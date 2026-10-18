import { isAllowedPath, tmdb } from "@/lib/tmdb";

/** Read-only TMDB proxy for client components, so the API key stays on the server. */
export async function GET(request: Request, { params }: RouteContext<"/api/tmdb/[...path]">) {
  const { path: segments } = await params;
  const path = segments.join("/");
  if (!isAllowedPath(path)) {
    return Response.json({ error: "Not allowed" }, { status: 400 });
  }
  const query = Object.fromEntries(new URL(request.url).searchParams);
  try {
    const data = await tmdb(path, query);
    return Response.json(data, {
      headers: { "Cache-Control": "public, max-age=3600, s-maxage=86400, stale-while-revalidate=604800" },
    });
  } catch (e) {
    return Response.json({ error: (e as Error).message }, { status: 502 });
  }
}
