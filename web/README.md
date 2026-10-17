# WatchGuide for the web

The web version of WatchGuide, built with Next.js 16 (App Router, Cache Components), React 19 and Tailwind 4.

## Run it

```bash
cp .env.example .env.local   # then fill in the keys
npm install
npm run dev
```

| Variable | Needed for |
|---|---|
| `TMDB_API_KEY` | Everything. All TMDB calls go through the server, so the key never reaches the browser. |
| `OPENROUTER_API_KEY` | Atlas chat. Without it Atlas shows a "not set up" message. |
| `ATLAS_MODEL` | Optional. OpenRouter model id, defaults to `openai/gpt-5-nano`. |
| `ATLAS_ENDPOINT` | Optional. Any OpenAI-compatible chat completions URL. |
| `NEXT_PUBLIC_PADDLE_CLIENT_TOKEN`, `NEXT_PUBLIC_PADDLE_ENV`, `NEXT_PUBLIC_PADDLE_PRICE_ANNUAL`, `NEXT_PUBLIC_PADDLE_PRICE_MONTHLY` | WatchGuide Pro checkout with Paddle.js. Use a sandbox token (`test_…`) and `sandbox` locally. Without them the paywall says Pro is iOS-only for now. |
| `REVENUECAT_PADDLE_API_KEY` | Server-side. The public API key of the RevenueCat Paddle app; `/api/pro` uses it to read and confirm the Pro entitlement. |

## What's here

| Route | iOS counterpart |
|---|---|
| `/` Browse | `BrowseView`: hero carousel, Top 10, chapters and spotlights from `plan.md` |
| `/search` | `SearchView` |
| `/tonight` | `TonightReelView`: swipe deck with undo, arrow-key controls |
| `/title/[type]/[id]` | `MediaDetailView`: trailer, where to watch, episode tracker, payoff curve, time to finish |
| `/person/[id]`, `/collection/[id]` | `PersonDetailView`, franchise timeline |
| `/lists` | `ListsView`: Watchlist, Watching, Watched, Liked, custom lists |
| `/discover` | `MoodDiscoveryView` and genre browsing |
| `/streamq` | `MyStreamingView` |
| `/pops` | `ClipsView`: vertical trailer feed with Reels gestures (one clip per swipe, tap to pause, double-tap to like, hold to pause, scrub bar, loop, ↑/↓ J/K M on desktop) |
| `/calendar` | `CountdownCalendarView` |
| `/hubs`, `/hubs/[slug]` | Studio and network hubs |
| `/stats` | `StatsInsightsView` |
| `/atlas` | `AIAssistantView` (text chat with trailer embeds) |
| `/settings` | Themes from `ThemePack.swift`, region, backup and restore |

## Looks like iOS

The web app follows the iOS and iPadOS design: the same tabs (Browse, StreamQ, Pops, More, Search) in a floating Liquid Glass bar at the bottom on phones and at the top on iPad-width screens and up, large titles, glass buttons (`.glass`, `.glass-clear` in `globals.css`), system-blue selection (`--tint`), a poster-tinted title sheet, and Tonight as a full-screen reel. Compare against `AppStoreScreenshots/source/` when changing a screen.

- **Liquid Glass material** (`src/components/liquid-glass.tsx`): every `.glass` / `.glass-clear` surface gets an SVG displacement filter, drawn for its own size and corner radius and used as its `backdrop-filter`. The rim bends the background like a thick lens, with a faint colour fringe and a saturation lift, plus a specular edge highlight from CSS. Only Chromium renders SVG backdrop filters (Chrome on Android, desktop Chrome and Edge); Safari and Firefox keep the frosted-blur fallback.
- **Autoplaying trailers** (`src/components/auto-trailer.tsx`): the Browse hero plays each slide's trailer muted after its artwork, shows a progress bar in place of the dots, and moves on when it ends; title pages play the trailer in the header. One shared mute button and the three iOS toggles in Settings (Auto-play Trailers, Mute Trailers on Autoplay, Show Trailers in Media Details). Off under reduced motion.
- **Draggable tab bar** (`src/components/nav.tsx`): as on iOS 26, press the bar and slide; a glass lens follows your finger and releasing selects the tab under it. In Chromium the lens is a sibling of the bar with an SVG backdrop filter, so it magnifies and refracts everything under it, the page behind the bar included; elsewhere it carries a magnified copy of the tab row. Taps behave as normal links.

## WatchGuide Pro (RevenueCat)

`src/lib/purchases.ts` uses `@revenuecat/purchases-js` against the same RevenueCat project, `watchguide_pro` entitlement and current ("default") offering as the iOS app. `/pro` is the paywall, modelled on `WGUnlimitedPaywallView`: annual (with savings and any free trial) and monthly, checkout in RevenueCat's own sheet. Free limits follow `AIMessageQuota.swift`: 5 Atlas questions a day, 3 custom lists, and Stats behind Pro (`ProGate`).

- No accounts yet: each browser gets an anonymous RevenueCat user ID, so a web purchase unlocks Pro in that browser only. Sharing Pro with the iOS app needs sign-in and `Purchases.changeUser`.
- The Atlas quota is counted in the browser; enforcing it on the server needs accounts too.
- Going live: connect Stripe in RevenueCat, add a Web Billing app, create the Pro monthly/annual web products, attach them to `watchguide_pro` and to the `$rc_monthly` / `$rc_annual` packages, then set the `rcb_` key.
- Theme packs stay iOS purchases.

## Android

WatchGuide installs as an app from Chrome, Samsung Internet or Edge on Android ("Install WatchGuide" in More, or the browser's Install app menu). It opens full-screen with its own icon and adaptive (maskable) icon, home-screen shortcuts to Search, Tonight and Lists, a status bar that follows the active theme, and an offline page.

- `src/app/manifest.ts`: web app manifest
- `public/sw.js`: service worker (production only). It caches build assets and TMDB images and serves `/offline` when there's no connection
- `src/components/pwa.tsx`: service worker registration, install button, theme-color sync
- `public/icons/`: 192, 512 and maskable 512 icons

Android only offers installation over HTTPS (or `localhost`), so testing on a phone needs the deployed site or a tunnel.

## Not ported

Apple-only features are left out on purpose: Siri and Shortcuts intents, widgets, Live Activities, Visual Intelligence and the scanner, Wallet passes, CloudKit, StoreKit purchases, Apple Intelligence, and Atlas voice.

Accounts and Supabase sync aren't wired up yet. Everything a person saves lives in `localStorage` (`src/lib/store.ts`), with JSON export and import in Settings. Paid theme packs can be previewed but are bought in the iOS app.

## Layout

- `src/lib/tmdb.ts`: server-only cached TMDB client (`"use cache"` + `cacheLife`)
- `src/app/api/tmdb/[...path]`: allow-listed read-only proxy for client components
- `src/lib/api.ts`: client fetch helper and `useApi` hook
- `src/lib/store.ts`: local store for lists, progress, ratings and settings
- `src/lib/themes.ts`: theme palettes, emitted as CSS variables in the root layout
