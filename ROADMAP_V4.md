# WatchGuide v4 — "The app that knows where you are in every story"

## Positioning
Trackers log what you watched. Discovery apps tell you what to watch. **WatchGuide v4 guards and guides the watching itself** — before (should I start / is it worth it / what will it cost), during (a companion that never spoils), and after (protect me until I catch up).

The moat is one data point no competitor combines: **your exact position in every story** (WatchHour sessions + episode progress) joined with **your money** (StreamQ services + pricing).

Market check (Sept 2026): TV Time shut down 15 Jul 2026 (26M installs, history deleted) → displaced users. Spoiler apps (Spoilerblock, Hide Spoilers) are keyword/calendar-based. FlickWhisper does AI commentary but syncs by manual timer. No app predicts where you'll quit a show or prices a single show.

## Four pillars

### Pillar 1 — Stick With It ("abandonment insurance") · *nobody does this*
Tells you whether a show is worth pushing through, and exactly when it gets good.

- **Payoff Curve** on every show detail page: an episode-by-episode line of ratings (TMDB season details, Trakt episode ratings) with the **"it gets good" episode** marked and the **drop-off valley** shaded.
- **"You're in the valley" nudge**: when WatchHour sees you stall inside the valley (no session for N days), push: *"93% of people who reach S1E6 finish the season. You're 2 episodes away."*
- **Minutes-to-payoff**: "It gets good in 94 minutes" — runtime sum to the payoff episode. Works as a Live Activity countdown.
- **Honest Quit button**: if the curve never rises, say so: *"It doesn't get better. Here are 3 shows with your taste that start strong."* Quitting guilt-free is part of the wow.
- **Personal Stall Profile**: learns *your* pattern ("you quit dramas after episode 3, comedies never") and adjusts predictions.
- **Community drop-off map (v4.2)**: anonymised, opt-in aggregate of where WatchGuide users stop (Supabase). Becomes proprietary data over time.
- **Renewal risk badge**: "Ends on a cliffhanger — 70% cancellation risk." Status from TMDB (`status`, `in_production`) + curated signal; displayed *before* you start.

**Builds on:** `TMDBService.getSeasonDetails`, `TraktService`, `WatchHourService`, `ContinueWatchingService`, `ReleaseActivityAttributes`.

### Pillar 2 — Spoiler Firewall · *progress-aware, not keyword-aware*
Your progress becomes a shield.

- **Auto-shield**: every show in progress automatically generates spoiler terms (character names, actors, episode titles *beyond your position*, "finale", "dies", season N+1) — no manual keywords.
- **Safari content-blocker extension**: blurs matching text, thumbnails and links; tap-and-hold to reveal. Rules regenerate whenever WatchHour records progress.
- **Screen Time shield on drop day**: when a new episode airs and you haven't watched it, optionally block X/Reddit/TikTok (FamilyControls/ManagedSettings) until you log the episode or the timer ends. Lock-screen Live Activity: *"Shield up — The Bear S4E1 dropped 2h ago."*
- **Spoiler-safe everything in-app**: overviews, cast lists, stills, Atlas answers, widgets and notifications are all filtered to your current episode.
- **Household firewall**: per-profile position, so a shared iPad shows each person only what they've reached.
- **"Safe to read" button** on any article/Reddit link shared into WatchGuide: Atlas reads it and replies *"Safe"* or *"Contains S3 spoilers."*

**Builds on:** `ProfileService`, `WatchHourService`, `WidgetDataService`, `ContentFilterService`, Atlas.
**Constraint:** iOS can only filter Safari and Screen-Time-block apps; it cannot blur inside third-party apps. Be explicit in marketing.

### Pillar 3 — Atlas Watch-Along · *hands-free sync, beats manual timers*
A voice companion that knows the exact second you're at and never talks past it.

- **Auto-sync without a timer** (the hard, magical part):
  1. **Dialogue sync** — on-device `SFSpeechRecognizer` transcribes ~10 s of TV audio; fuzzy-match against timed subtitles (OpenSubtitles API) to lock the timestamp. Works for any service, no DRM touched.
  2. **Soundtrack sync** — ShazamKit identifies licensed songs; map song cue → known scene timestamp as a second anchor.
  3. Re-sync silently every few minutes; handles pauses and skipped intros.
- **Ask the movie**: "Who's that?", "Did I miss something?", "Why is he angry?" — answered from subtitles *up to the current second only*. Zero spoilers by construction.
- **Whisper mode**: optional trivia cues timed to scenes (from `DidYouKnowView`/trivia data), delivered to AirPods only so the room isn't disturbed.
- **Fell-asleep catch-up**: Apple Watch detects sleep → marks the timestamp → next day Atlas gives a 60-second recap of what you slept through.
- **"Previously, for you"**: before a new season, a 3-minute spoken recap generated only from the episodes *you* watched; plays in CarPlay on the drive home on drop night.
- **Big-screen mode**: Watch-Along works in the cinema in text-only, dark, haptic-only form (e.g. "mid-credits scene coming — stay").

**Builds on:** `AtlasVoiceSession`, `AtlasInlineVoice`, `AtlasMemoryStore`, `AtlasPersona`, trivia views, `CinemaTripPlannerService`.

### Pillar 4 — The Bill · *money meets story*
- **Show price tag** on detail pages: *"Severance S1–2: 19 hrs · ~3 weeks at your pace · R179 on Apple TV+ (1 month)."* Pace from WatchHour history.
- **Cost-per-hour dashboard** per service, graded (<R25/h great, >R70/h wasted — ZAR thresholds scaled from the US $1.50/$4 benchmark).
- **Rotation planner**: calendar of which service to hold each month to finish your watchlist cheapest, respecting `LeavingSoonService` departure dates.
- **"Nothing left" alert**: you've finished everything you care about on a service → *"Pause Disney+ before 3 Oct and save R119."*
- **Loadshedding pack (ZA)**: EskomSePush schedule → *"Stage 4 at 18:00 for 2h. Download these 2 episodes now."* (reminder + deep link; iOS can't trigger another app's downloads).

**Builds on:** `ProviderPricingService`, `LeavingSoonService`, `MyStreamingView` (StreamQ), `StreamingDeepLinkService`.

## Wow moments to demo (App Store preview / launch video)
1. Hold phone toward TV → 3 s later "Synced — Dune: Part Two, 1:12:40" → ask "who's that?" out loud → answer in AirPods.
2. Stall on a show → lock screen: "It gets good in 94 minutes." with the payoff curve.
3. New episode drops → Reddit link opens blurred → "Shield up until you watch."
4. Show page: "R179 and 3 weeks. Cancel on the 2nd." 
5. Fall asleep → morning notification: "You slept through 26 minutes. Here's the 60-second version."

## Release plan

| Version | Theme | Scope | Exit criteria |
|---|---|---|---|
| **4.0.0** | Stick With It + The Bill (foundation) | Payoff Curve, minutes-to-payoff, stall nudges, honest quit, show price tag, cost-per-hour dashboard, TV Time import landing, IA cleanup (merge Browse/StreamQ/More, move studio hubs & trivia under Search) | Curve renders for 95% of TMDB shows; nudge opt-in ≥40% |
| **4.1.0** | Spoiler Firewall | Auto-generated terms, Safari content blocker extension, in-app spoiler-safe filtering, household per-profile position | Blocker rules regenerate < 2 s after progress change |
| **4.2.0** | Atlas Watch-Along (beta) | Dialogue + soundtrack sync, ask-the-movie, whisper trivia, TestFlight only | Sync lock < 10 s in 80% of trials; zero spoiler answers in eval set |
| **4.3.0** | Money & life | Rotation planner, "nothing left" alert, loadshedding pack, Screen Time drop-day shield, community drop-off map | Rotation saves ≥ 1 service/month for active users |
| **4.4.0** | Magic polish | Fell-asleep catch-up (Watch), "Previously, for you" CarPlay recap, cinema big-screen mode, personal Stall Profile | — |

Bug-fix releases (`4.x.1`) follow each feature release, per the v3 versioning model.

## New components (proposed)
- `Services/PayoffCurveService.swift` — fetch/cached episode ratings, detect valley + payoff episode, minutes-to-payoff.
- `Services/StallDetectionService.swift` — watches WatchHour history, schedules nudges, builds Stall Profile.
- `Services/SpoilerFirewallService.swift` — term generation per profile; writes shared rules to App Group.
- `SpoilerShieldExtension/` — Safari content blocker target reading App Group rules.
- `Services/WatchAlongSyncService.swift` — speech capture, subtitle matching, ShazamKit anchors, timestamp clock.
- `Services/SubtitleTimelineService.swift` — OpenSubtitles fetch + index (spoiler cutoff by timestamp).
- `Services/ShowBillService.swift` — pace × runtime × pricing; rotation planner.
- `Services/LoadsheddingService.swift` — EskomSePush API (needs key).
- Views: `PayoffCurveView`, `StickWithItCard`, `SpoilerShieldSettingsView`, `WatchAlongView`, `ShowBillCard`, `RotationPlannerView`.

## Risks & open questions
- **Data licensing**: OpenSubtitles API terms/commercial tier; EskomSePush API key; Trakt rate limits.
- **Privacy**: microphone use in Watch-Along must be on-device, visibly indicated, never stored. HealthKit sleep opt-in only.
- **iOS limits**: no blurring inside other apps; FamilyControls entitlement requires Apple approval.
- **Accuracy**: payoff curves on sparse-rated shows — fall back to "not enough data" rather than guessing.
- **Scope**: cut `BrowseView`/`SettingsView` sprawl before adding pillars, or v4 inherits v3's weight.
- **Decision needed**: free vs WG Unlimited split — proposal: Payoff Curve + in-app spoiler safety free; Watch-Along, Safari shield, rotation planner in Unlimited (`WGUnlimitedPaywallView`).
