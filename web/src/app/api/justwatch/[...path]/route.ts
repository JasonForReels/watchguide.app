import { justwatch } from "@/lib/justwatch";

/** Read-only JustWatch (RapidAPI) proxy shared by the web app and the iOS app. */
export async function GET(request: Request, { params }: RouteContext<"/api/justwatch/[...path]">) {
  const { path: segments } = await params;
  const query = Object.fromEntries(new URL(request.url).searchParams);
  try {
    const data = await justwatch(`api/justwatch/${segments.join("/")}`, query);
    return Response.json(data, {
      headers: { "Cache-Control": "public, max-age=300, s-maxage=3600" },
    });
  } catch (e) {
    return Response.json({ error: (e as Error).message }, { status: 502 });
  }
}
