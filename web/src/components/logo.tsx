/** The WatchGuide mark: concentric rings around a play glyph, after the app icon. */
export function Logo({ className = "" }: { className?: string }) {
  return (
    <svg viewBox="0 0 64 64" className={className} aria-hidden="true">
      <defs>
        <linearGradient id="wg-bg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stopColor="#A3149C" />
          <stop offset="1" stopColor="#5E0459" />
        </linearGradient>
      </defs>
      <rect width="64" height="64" rx="15" fill="url(#wg-bg)" />
      <g fill="none" stroke="#F3D7EF" strokeLinecap="round">
        <circle cx="32" cy="32" r="20" strokeWidth="3.4" />
        <circle cx="32" cy="32" r="15.5" strokeWidth="1.6" opacity="0.85" />
        <circle cx="32" cy="32" r="13" strokeWidth="1.6" opacity="0.85" />
      </g>
      <path d="M27.5 24.5c0-1.3 1.4-2.1 2.5-1.4l10.3 6.6c1 .7 1 2.1 0 2.8L30 39c-1.1.7-2.5-.1-2.5-1.4z" fill="#F3D7EF" />
    </svg>
  );
}
