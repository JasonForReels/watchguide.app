/**
 * Atlas chat. Streams plain text from an OpenAI-compatible endpoint
 * (OpenRouter by default). The system prompt is a trimmed port of
 * `AIService.buildSystemPrompt` without the iOS-only tags.
 */

const ENDPOINT = process.env.ATLAS_ENDPOINT ?? "https://openrouter.ai/api/v1/chat/completions";

const SYSTEM = `You are Atlas, an AI movie & TV assistant inside WatchGuide. Concise but complete — never cut off mid-sentence.

Rules:
- For simple questions: 2-4 sentences, straight to the point.
- For recommendations: give exactly 2 movies and 2 TV shows. Each with **Title** (Movie/Show) + a short reason (one line).
- Use **bold** for titles. No fluff, no disclaimers, no preamble.
- Be casual and fun, like texting a film-buff friend.
- Use bullet points for lists.
- TRAILER EMBEDDING: When discussing one specific movie or show and a trailer would help, put [TRAILER:Exact Title] at the very END of your response. Only one per response. Never mention the tag.
- NO RUMOURS: Only state what has been officially announced, confirmed, or released. If something is unannounced, say there is no official announcement yet.
- Never repeat yourself. State each fact once.
- Keep content suitable for ages 13+. Decline requests for explicit sexual content, and don't help find pirated copies.`;

interface Msg {
  role: "user" | "assistant";
  content: string;
}

export async function POST(request: Request) {
  const key = process.env.OPENROUTER_API_KEY;
  if (!key) {
    return Response.json({ error: "Atlas isn't set up on this server. Add OPENROUTER_API_KEY to .env.local." }, { status: 503 });
  }

  let body: { messages?: Msg[]; taste?: string[] };
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "Bad request" }, { status: 400 });
  }

  const messages = (body.messages ?? [])
    .filter((m) => (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
    .slice(-12)
    .map((m) => ({ role: m.role, content: m.content.slice(0, 4000) }));
  if (!messages.length || messages.at(-1)?.role !== "user") {
    return Response.json({ error: "Send a message first." }, { status: 400 });
  }

  const taste = (body.taste ?? []).slice(0, 15).map((t) => String(t).slice(0, 80));
  const system = taste.length ? `${SYSTEM}\n\nUser's taste (liked): ${taste.join(", ")}` : SYSTEM;

  const upstream = await fetch(ENDPOINT, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      "HTTP-Referer": "https://watchguide.app",
      "X-Title": "WatchGuide",
    },
    body: JSON.stringify({
      model: process.env.ATLAS_MODEL ?? "openai/gpt-5-nano",
      stream: true,
      messages: [{ role: "system", content: system }, ...messages],
    }),
    signal: request.signal,
  });

  if (!upstream.ok || !upstream.body) {
    const status = upstream.status === 429 ? 429 : 502;
    const error = status === 429 ? "Atlas is busy right now. Try again in a moment." : "Atlas couldn't reach the model. Try again.";
    return Response.json({ error }, { status });
  }

  // Convert the SSE stream into plain text deltas.
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();
  let buffer = "";
  const stream = upstream.body.pipeThrough(
    new TransformStream<Uint8Array, Uint8Array>({
      transform(chunk, controller) {
        buffer += decoder.decode(chunk, { stream: true });
        const lines = buffer.split("\n");
        buffer = lines.pop() ?? "";
        for (const line of lines) {
          const data = line.trim();
          if (!data.startsWith("data:")) continue;
          const payload = data.slice(5).trim();
          if (payload === "[DONE]") continue;
          try {
            const delta = JSON.parse(payload).choices?.[0]?.delta?.content;
            if (delta) controller.enqueue(encoder.encode(delta));
          } catch {
            // Keep-alive comments and partial frames are skipped.
          }
        }
      },
    }),
  );

  return new Response(stream, { headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } });
}
