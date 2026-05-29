# Plan: Break the Infinite-Scroll Monotony in WatchGuide

## Problem
The Browse view is a `LazyVStack(spacing: 24)` that renders a hero carousel followed by a long sequence of visually identical `MediaRowView` sections (horizontal poster rows), all with the same poster size, same header style, and same horizontal scroll pattern. The result feels like an endless, undifferentiated feed.

## Diagnosis
- **`browseRowsSection`** iterates `viewModel.rows` and renders every media row through the same `MediaRowView` component with identical sizing, spacing, and layout.
- There is no variation in card size, layout direction, or visual weight between sections.
- The only visual breaks are the hero carousel at top, an occasional `ComingSoonRowView` or `PeopleRowView`, and studio logos — but the bulk of content is uniform poster rows.

## Proposed Changes

### 1. Spotlight Feature Card (new component)
**File:** `Views/Components/SpotlightCardView.swift` (new)

Insert a large, full-width "spotlight" card after every 3rd media row. This card picks one item from the *next* row's data and renders it as a cinematic backdrop card with:
- Full-width backdrop image (16:9)
- Gradient overlay with title, year, and overview snippet
- Tap to open detail

This breaks the horizontal-scroll monotony with a full-bleed vertical element.

### 2. Dual-Poster Row Variant
**File:** `Views/Components/MediaRowView.swift` (modify)

Add a `style` parameter to `MediaRowView` with two modes:
- `.standard` — current horizontal scroll of portrait posters (default)
- `.featured` — shows the first 2-3 items as larger landscape backdrop cards side-by-side in a horizontal scroll, then the rest as standard posters

Apply `.featured` style to every 4th media row (e.g., rows at index 0, 4, 8...) to create visual rhythm.

### 3. Numbered Ranking Row Enhancement
**File:** `Views/Components/MediaRowView.swift` (modify)

The trending rows already show rank badges, but they use the same poster size as everything else. For rows with `isRankedTrendingRow == true`, increase poster height by ~30% and add a large rank number beside each poster (Netflix "Top 10" style). This makes trending rows visually distinct without a new component.

### 4. Section Dividers with Context
**File:** `Views/BrowseView.swift` (modify)

Between every 3-4 rows, insert a thin contextual divider/section header that groups content thematically (e.g., "Trending Now", "New Releases", "For You"). This gives the scroll natural "chapters" rather than one continuous stream.

### 5. Staggered Section Spacing
**File:** `Views/BrowseView.swift` (modify)

Replace the uniform `spacing: 24` in the `LazyVStack` with variable spacing: tighter spacing (16pt) between rows within the same "chapter" and wider spacing (40pt) between chapters. This creates visual breathing room.

## Implementation Order

1. **SpotlightCardView** — New component, biggest visual impact, no risk to existing code
2. **Section dividers + staggered spacing** — Small changes in BrowseView, groups content into chapters
3. **Featured row style** — Modifies MediaRowView to alternate card sizes
4. **Trending rank enhancement** — Enhances existing rank badge display

## Files Changed
| File | Change Type |
|------|-------------|
| `Views/Components/SpotlightCardView.swift` | New |
| `Views/Components/MediaRowView.swift` | Modify (add featured style + bigger trending) |
| `Views/BrowseView.swift` | Modify (insert spotlights, dividers, variable spacing) |

## What This Does NOT Change
- No changes to data fetching, view models, or services
- No changes to navigation, presentation logic, or platform-specific code
- No changes to DiscoverView, MediaDetailView, or other screens
- No changes to tvOS-specific layouts (changes scoped to iOS/iPadOS via size class checks)
