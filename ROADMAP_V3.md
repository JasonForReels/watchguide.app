# Watch Guide v3 Roadmap

Versioning model used in v3:
- `vX.0.0`: major platform update (new app generation)
- `vX.Y.0`: feature release
- `vX.Y.Z`: bug fix / stabilization release

## v3.0.0 (Major Update)
Target: establish the v3 baseline and reliability across iPhone, iPad, and widget.

Planned scope:
- Harden profile sync (including custom avatar URL sync and conflict handling)
- Finalize avatar pipeline (remote feed compatibility and fallback behavior)
- Improve first-run/auth/profile selection flow to reduce dead-ends
- Improve cloud sync observability (clearer errors + retry paths)
- Performance pass on home/browse loading and image prefetch behavior
- Ship migration notes from 2.x to 3.0.0

Exit criteria:
- Clean compile for app + widget extension
- No critical sync regressions in cross-device profile tests
- Crash-free and successful launch metrics meet internal targets

## v3.1.0 (Feature Release)
Target: expand personalization and discovery quality.

Planned scope:
- Smarter recommendations and better profile-aware content rails
- More home customization options and saved layouts per profile
- Expanded list tooling (bulk actions, sort/filter improvements)
- Enhanced cinema trip planning UX and better showtime reliability
- Better onboarding for avatar/profile setup and family profiles

Exit criteria:
- Feature flags removed for shipped experiences
- Discovery and engagement improvements validated

## v3.1.1 (Bug Fix Release)
Target: stabilize v3.1.0 in production.

Planned scope:
- Fix high-priority crashes and UI regressions
- Resolve sync edge cases reported post-release
- Patch widget refresh and timeline issues
- Tighten memory and network usage hotspots

Exit criteria:
- No P0/P1 open issues
- Regression suite passes for profile + sync + widget

## v3.2.0 (Feature Release)
Target: quality-of-life and ecosystem improvements.

Planned scope:
- Deeper stats/insights and timeline enhancements
- Better sharing/export options for lists and picks
- Accessibility pass (dynamic type, contrast, voiceover polish)
- Localization readiness improvements

## v3.2.1 (Bug Fix Release)
Target: post-feature stabilization and polish.

Planned scope:
- Fixes from v3.2.0 telemetry and user feedback
- UI polish and consistency cleanup
- Additional reliability patches in cloud sync and media fetching

## Ongoing Across v3.x
- Security and dependency updates
- API compatibility checks (TMDB/OMDb/Supabase)
- Test coverage expansion in unit + UI automation
