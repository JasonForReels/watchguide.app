"use client";

import Link from "next/link";
import { Fragment, useEffect, useRef, useState, useSyncExternalStore } from "react";
import { ArrowUp, Play, RotateCcw, Square } from "lucide-react";
import { Logo } from "@/components/logo";
import { TrailerModal } from "@/components/trailer";
import { api } from "@/lib/api";
import { atlasMessagesLeft, consumeAtlasMessage, FREE_LIMITS, usePro } from "@/lib/purchases";
import { getState } from "@/lib/store";
import { titleOf, typeOf } from "@/lib/media";
import type { MediaItem, Paged, Video } from "@/lib/types";

interface Msg {
  role: "user" | "assistant";
  content: string;
}

const SUGGESTIONS = [
  "Something like Severance but lighter",
  "A great film under 90 minutes",
  "What should I watch after Breaking Bad?",
  "Best heist movies of the last decade",
];

const TRAILER_TAG = /\[TRAILER:([^\]]+)\]/;

/** Bold titles become search links; [text](https://…) becomes a link. Nothing else is interpreted. */
function inline(text: string) {
  const parts = text.split(/(\*\*[^*]+\*\*|\[[^\]]+\]\(https?:\/\/[^)\s]+\))/g);
  return parts.map((p, i) => {
    const bold = p.match(/^\*\*([^*]+)\*\*$/);
    if (bold) {
      const t = bold[1].replace(/\s*\((Movie|Show|TV|Film|TV Show)\)\s*$/i, "");
      return <Link key={i} href={`/search?q=${encodeURIComponent(t)}`} className="font-semibold text-accent hover:underline">{bold[1]}</Link>;
    }
    const link = p.match(/^\[([^\]]+)\]\((https?:\/\/[^)\s]+)\)$/);
    if (link) return <a key={i} href={link[2]} target="_blank" rel="noreferrer" className="text-accent underline">{link[1]}</a>;
    return <Fragment key={i}>{p}</Fragment>;
  });
}

function Rich({ text }: { text: string }) {
  const lines = text.replace(TRAILER_TAG, "").trim().split("\n");
  const out: React.ReactNode[] = [];
  let bullets: string[] = [];
  const flush = () => {
    if (bullets.length) out.push(<ul key={out.length} className="my-2 list-disc space-y-1 pl-5">{bullets.map((b, i) => <li key={i}>{inline(b)}</li>)}</ul>);
    bullets = [];
  };
  for (const line of lines) {
    const m = line.match(/^\s*[-*•]\s+(.*)/);
    if (m) bullets.push(m[1]);
    else {
      flush();
      if (line.trim()) out.push(<p key={out.length} className="my-1.5">{inline(line.replace(/^#+\s*/, ""))}</p>);
    }
  }
  flush();
  return <>{out}</>;
}

function TrailerCard({ title }: { title: string }) {
  const [found, setFound] = useState<{ item: MediaItem; video: Video } | null | undefined>(undefined);
  const [open, setOpen] = useState(false);

  useEffect(() => {
    let live = true;
    (async () => {
      const r = await api<Paged<MediaItem>>("search/multi", { query: title });
      const item = r.results.find((i) => i.media_type !== "person");
      if (!item) return live && setFound(null);
      const v = await api<{ results: Video[] }>(`${typeOf(item)}/${item.id}/videos`);
      const video = v.results.find((x) => x.site === "YouTube" && x.type === "Trailer") ?? v.results.find((x) => x.site === "YouTube");
      if (live) setFound(video ? { item, video } : null);
    })().catch(() => live && setFound(null));
    return () => {
      live = false;
    };
  }, [title]);

  if (!found) return null;
  return (
    <>
      <button type="button" onClick={() => setOpen(true)} className="group relative mt-3 block aspect-video w-full max-w-sm overflow-hidden rounded-xl bg-black">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src={`https://i.ytimg.com/vi/${found.video.key}/hqdefault.jpg`} alt="" className="h-full w-full object-cover opacity-80 transition group-hover:opacity-100" />
        <span className="absolute inset-0 grid place-items-center">
          <span className="grid size-14 place-items-center rounded-full bg-accent text-on-accent shadow-xl"><Play className="ml-0.5 size-6 fill-current" /></span>
        </span>
        <span className="absolute bottom-0 left-0 p-2.5 text-left text-sm font-semibold text-white drop-shadow">{titleOf(found.item)} · Trailer</span>
      </button>
      {open && <TrailerModal videoKey={found.video.key} title={titleOf(found.item)} onClose={() => setOpen(false)} />}
    </>
  );
}

const noop = () => () => {};

export function AtlasChat() {
  const pro = usePro();
  // Re-read after each message; localStorage has no change event within the same tab.
  const [, bump] = useState(0);
  const left = useSyncExternalStore(noop, atlasMessagesLeft, () => FREE_LIMITS.atlasMessagesPerDay);
  const limited = !pro.isPro && pro.status !== "unavailable" && pro.status !== "loading";
  const outOfQuestions = limited && left <= 0;
  const [messages, setMessages] = useState<Msg[]>([]);
  const [input, setInput] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const abort = useRef<AbortController | null>(null);
  const end = useRef<HTMLDivElement>(null);

  useEffect(() => {
    end.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [messages]);

  async function send(text: string) {
    const content = text.trim();
    if (!content || busy || outOfQuestions) return;
    if (limited) {
      consumeAtlasMessage();
      bump((n) => n + 1);
    }
    setError(null);
    setInput("");
    const history: Msg[] = [...messages, { role: "user", content }];
    setMessages([...history, { role: "assistant", content: "" }]);
    setBusy(true);
    const controller = new AbortController();
    abort.current = controller;
    const s = getState();
    const taste = [...s.lists.liked, ...s.lists.watched].slice(0, 15).map((i) => `${i.title} (${i.type === "movie" ? "M" : "TV"})`);

    try {
      const res = await fetch("/api/atlas", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ messages: history, taste }),
        signal: controller.signal,
      });
      if (!res.ok || !res.body) {
        const j = await res.json().catch(() => ({}));
        throw new Error(j.error ?? "Atlas couldn't answer. Try again.");
      }
      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let acc = "";
      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        acc += decoder.decode(value, { stream: true });
        setMessages([...history, { role: "assistant", content: acc }]);
      }
      if (!acc.trim()) throw new Error("Atlas didn't say anything. Try rephrasing.");
    } catch (e) {
      if ((e as Error).name !== "AbortError") {
        setError((e as Error).message);
        setMessages((m) => (m.at(-1)?.content ? m : m.slice(0, -1)));
      }
    } finally {
      setBusy(false);
      abort.current = null;
    }
  }

  return (
    <div className="mx-auto flex min-h-[calc(100dvh-6rem)] max-w-3xl flex-col px-4 pt-8 sm:px-8 lg:min-h-dvh lg:pt-10">
      <header className="mb-6 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Logo className="size-10" />
          <div>
            <h1 className="font-display text-2xl font-bold tracking-tight">Atlas</h1>
            <p className="text-sm text-muted">Your movie and TV guide</p>
          </div>
        </div>
        {messages.length > 0 && (
          <button type="button" onClick={() => { abort.current?.abort(); setMessages([]); setError(null); }} className="inline-flex items-center gap-1.5 text-sm text-muted hover:text-text">
            <RotateCcw className="size-4" /> New chat
          </button>
        )}
      </header>

      <div className="flex-1 space-y-5 pb-6">
        {!messages.length && (
          <div className="rise py-10 text-center">
            <p className="font-display text-2xl font-semibold">What are you in the mood for?</p>
            <p className="mt-1 text-muted">Ask for picks, trivia, or what to watch next. Atlas knows what you&apos;ve liked.</p>
            <div className="mx-auto mt-6 grid max-w-xl gap-2 sm:grid-cols-2">
              {SUGGESTIONS.map((s) => (
                <button key={s} type="button" onClick={() => send(s)} className="rounded-card bg-surface px-4 py-3 text-left text-sm ring-1 ring-line transition hover:ring-accent">
                  {s}
                </button>
              ))}
            </div>
          </div>
        )}
        {messages.map((m, i) => {
          const trailer = m.role === "assistant" && !(busy && i === messages.length - 1) ? m.content.match(TRAILER_TAG)?.[1] : undefined;
          return (
            <div key={i} className={m.role === "user" ? "flex justify-end" : ""}>
              {m.role === "user" ? (
                <p className="max-w-[85%] rounded-2xl rounded-br-md bg-accent px-4 py-2.5 text-[15px] text-on-accent">{m.content}</p>
              ) : (
                <div className="max-w-[92%] text-[15px] leading-relaxed">
                  {m.content ? <Rich text={m.content} /> : <span className="inline-flex gap-1 py-2">{[0, 1, 2].map((d) => <span key={d} className="size-2 animate-bounce rounded-full bg-accent" style={{ animationDelay: `${d * 120}ms` }} />)}</span>}
                  {trailer && <TrailerCard title={trailer} />}
                </div>
              )}
            </div>
          );
        })}
        {error && <p className="rounded-card bg-red-500/10 px-4 py-3 text-sm text-red-300 ring-1 ring-red-500/30">{error}</p>}
        <div ref={end} />
      </div>

      {outOfQuestions ? (
        <Link href="/pro" className="press sticky bottom-28 mb-4 flex items-center justify-between gap-4 rounded-2xl bg-surface p-4 shadow-2xl ring-1 ring-line md:bottom-4">
          <span>
            <span className="block font-semibold">That&apos;s your {FREE_LIMITS.atlasMessagesPerDay} free questions for today</span>
            <span className="text-sm text-muted">Ask Atlas anything, without limits, with WatchGuide Pro.</span>
          </span>
          <span className="shrink-0 rounded-full bg-accent px-4 py-2 text-sm font-semibold text-white">Get Pro</span>
        </Link>
      ) : (
      <form
        onSubmit={(e) => {
          e.preventDefault();
          send(input);
        }}
        className="sticky bottom-28 mb-4 flex items-end gap-2 rounded-2xl bg-surface p-2 shadow-2xl ring-1 ring-line focus-within:ring-accent md:bottom-4"
      >
        <textarea
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !e.shiftKey) {
              e.preventDefault();
              send(input);
            }
          }}
          rows={1}
          placeholder="Ask Atlas…"
          aria-label="Message Atlas"
          className="max-h-40 min-h-10 flex-1 resize-none bg-transparent px-2 py-2 text-[15px] outline-none"
        />
        {busy ? (
          <button type="button" onClick={() => abort.current?.abort()} aria-label="Stop" className="grid size-10 place-items-center rounded-xl bg-raised"><Square className="size-4 fill-current" /></button>
        ) : (
          <button type="submit" disabled={!input.trim()} aria-label="Send" className="grid size-10 place-items-center rounded-xl bg-accent text-on-accent disabled:opacity-40"><ArrowUp className="size-5" /></button>
        )}
        {limited && <span className="absolute -top-6 right-2 text-xs text-faint">{left} free question{left === 1 ? "" : "s"} left today</span>}
      </form>
      )}
    </div>
  );
}
