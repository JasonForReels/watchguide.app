"use client";

import { useState } from "react";
import { Loader2 } from "lucide-react";
import { signIn, signUp } from "@/lib/auth";

/** Email and password sign-in, the same accounts as the WatchGuide iOS app. */
export function AccountForm({ reason }: { reason: string }) {
  const [mode, setMode] = useState<"in" | "up">("in");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setMessage(null);
    const result = await (mode === "in" ? signIn : signUp)(email.trim(), password);
    setBusy(false);
    if (!result.ok) setMessage(result.message);
  };

  const field = "h-12 w-full rounded-[14px] bg-bg px-4 text-[17px] outline-none ring-1 ring-line focus:ring-tint";

  return (
    <form onSubmit={submit} className="mt-6 rounded-[22px] bg-surface p-4">
      <p className="text-[17px] font-semibold">{mode === "in" ? "Sign in" : "Create your account"}</p>
      <p className="mt-1 text-[14px] text-muted">{reason}</p>
      <div className="mt-3 space-y-2">
        <input
          type="email"
          autoComplete="email"
          required
          placeholder="Email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className={field}
        />
        <input
          type="password"
          autoComplete={mode === "in" ? "current-password" : "new-password"}
          required
          minLength={6}
          placeholder="Password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          className={field}
        />
      </div>
      <button
        type="submit"
        disabled={busy || !email || password.length < 6}
        className="press mt-3 flex h-12 w-full items-center justify-center gap-2 rounded-full bg-accent text-[17px] font-semibold text-white disabled:opacity-50"
      >
        {busy && <Loader2 className="size-5 animate-spin" />}
        {mode === "in" ? "Sign in" : "Create account"}
      </button>
      {message && <p className="mt-3 text-center text-[14px] text-red-400" role="alert">{message}</p>}
      <button
        type="button"
        onClick={() => { setMode(mode === "in" ? "up" : "in"); setMessage(null); }}
        className="mt-3 block w-full text-center text-[14px] font-medium text-tint"
      >
        {mode === "in" ? "New here? Create an account" : "Already have an account? Sign in"}
      </button>
    </form>
  );
}
