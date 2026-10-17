"use client";

import { useEffect, useState } from "react";

type Params = Record<string, string | number | undefined>;

const memory = new Map<string, Promise<unknown>>();

function urlFor(path: string, params: Params = {}): string {
  const qs = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== "") qs.set(k, String(v));
  const q = qs.toString();
  return `/api/tmdb/${path}${q ? `?${q}` : ""}`;
}

/** Fetch TMDB data through the server proxy. Identical requests share one promise per page load. */
export function api<T>(path: string, params?: Params): Promise<T> {
  const url = urlFor(path, params);
  let p = memory.get(url) as Promise<T> | undefined;
  if (!p) {
    p = fetch(url).then(async (r) => {
      if (!r.ok) throw new Error(`Request failed (${r.status})`);
      return r.json() as Promise<T>;
    });
    p.catch(() => memory.delete(url));
    memory.set(url, p);
  }
  return p;
}

export interface Loadable<T> {
  data: T | undefined;
  error: Error | undefined;
  loading: boolean;
}

/** Load a TMDB path in a client component. Pass `null` to skip. */
export function useApi<T>(path: string | null, params?: Params): Loadable<T> {
  const url = path ? urlFor(path, params) : null;
  const [state, setState] = useState<{ url: string | null; data?: T; error?: Error }>({ url: null });

  useEffect(() => {
    if (!path || !url) return;
    let live = true;
    api<T>(path, params).then(
      (data) => live && setState({ url, data }),
      (error: Error) => live && setState({ url, error }),
    );
    return () => {
      live = false;
    };
    // `url` captures path and params.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [url]);

  const current = state.url === url;
  return {
    data: current ? state.data : undefined,
    error: current ? state.error : undefined,
    loading: Boolean(url) && (!current || (!state.data && !state.error)),
  };
}
