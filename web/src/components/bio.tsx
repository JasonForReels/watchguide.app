"use client";

import { useState } from "react";

export function Bio({ text }: { text: string }) {
  const [open, setOpen] = useState(false);
  const long = text.length > 420;
  return (
    <div className="mt-4">
      <p className={`whitespace-pre-line text-[15px] leading-relaxed text-text/85 ${!open && long ? "line-clamp-5" : ""}`}>{text}</p>
      {long && (
        <button type="button" onClick={() => setOpen((o) => !o)} className="mt-2 text-sm font-medium text-accent hover:underline">
          {open ? "Show less" : "Read more"}
        </button>
      )}
    </div>
  );
}
