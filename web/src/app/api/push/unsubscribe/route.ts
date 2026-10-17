import { isPushEndpoint, removeDevice } from "@/lib/push-store";

/** Forgets a device when the person turns reminders off. */
export async function POST(request: Request) {
  const body = (await request.json().catch(() => null)) as { endpoint?: unknown } | null;
  if (!body || !isPushEndpoint(body.endpoint)) return Response.json({ error: "Invalid endpoint." }, { status: 400 });
  try {
    await removeDevice(body.endpoint);
  } catch {
    return Response.json({ error: "Storage unavailable." }, { status: 503 });
  }
  return Response.json({ ok: true });
}
