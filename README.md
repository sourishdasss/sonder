# Sonder — Travel that fits you

A native iOS app (Swift + SwiftUI, iOS 17+) where you rate the **places** you visited inside a city
rather than the city as a whole. Sonder turns those ratings into a city score, a travel personality
and recommendations for where to go next, with a social feed of what other travellers are rating.

## What's in the app

| Tab | What it does |
| --- | --- |
| **Feed** | Other travellers' visits. Filter by Everyone, Following or Trending (most-rated cities this week). |
| **Map** | A 3D globe with a pin for every city you've rated, plus location-tagged travel photos. |
| **Lists** | Your cities ranked by score, or every place you've rated grouped by category. |
| **Profile** | Travel personality, taste breakdown, stats, top cities, followers and "Where to Next". |

**Rating a city.** Search for any city or town in the world, add the places you visited (curated
suggestions, places other travellers added, or a MapKit search scoped to that city), say how each
one felt (*loved it / it was fine / not for me*) and settle ties with a few head-to-head
comparisons. Optionally rate the city's overall vibe, then save to see the score.

**Scoring.** Each place gets a 0–10 score from its sentiment band and its rank among similar
places. The city score is the category-weighted average:

| Category | Weight |
| --- | --- |
| Neighbourhoods & Walks, Overall vibe | 1.5 |
| Food & Markets | 1.2 |
| Museums & Culture, Parks & Nature, Experiences & Activities | 1.0 |
| Viewpoints & Landmarks | 0.8 |

Scores are always computed on-device (`ScoringEngine`), so they are deterministic and match the
per-place numbers shown in the app.

## Getting started

Requirements: Xcode 16 or newer. [XcodeGen](https://github.com/yonaskolb/XcodeGen) is only needed
if you change `project.yml`.

```bash
open Sonder.xcodeproj
```

Pick an iPhone simulator and run. To explore the app without any backend, add the launch argument
`-SonderDemoMode YES` (Product → Scheme → Edit Scheme → Run → Arguments). Demo mode is debug-only,
runs entirely in memory with sample data, and never touches the network backend.

### 1. Supabase

1. Create a project at [supabase.com](https://supabase.com).
2. Open the SQL editor and run **`supabase/schema.sql`**. It is idempotent and creates the tables,
   row-level security policies, the sign-up trigger, the `delete_user` function and the `photos`
   storage bucket. (`supabase/migrations/` holds the same changes as they were applied to the
   Sonder project, for use with the Supabase CLI.)
3. Put your project URL and anon key in **`Config/Sonder.xcconfig`**.

Free-plan projects are paused after a period of inactivity. If sign-in suddenly fails with
"couldn't reach the Sonder server", restore the project from the Supabase dashboard.

New accounts must confirm their email address before signing in (Supabase's default). The app
tells people to check their inbox; turn "Confirm email" off under Authentication → Sign In /
Providers if you want instant sign-up while testing.

Access model: any signed-in user can read profiles, rated cities, travel profiles, the feed and the
follow graph; people can only write their own rows. Photo pins are private to their owner.
Signed-out clients can read nothing.

### 2. Claude (optional)

Without an API key, summaries and the travel personality are written on-device. To have Claude
write them instead:

```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig
```

Then set `ANTHROPIC_API_KEY` in `Config/Secrets.xcconfig` (git-ignored). The model is set by
`CLAUDE_MODEL` in `Config/Sonder.xcconfig`. If a Claude request fails or times out, the app falls
back to the on-device copy, so saving a visit never depends on it.

> Anything compiled into an iOS app can be extracted from the binary. An embedded key is fine for
> personal builds and TestFlight; for a public App Store release, route Claude calls through a
> server you control.

## Tests

```bash
xcodebuild -project Sonder.xcodeproj -scheme Sonder -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

The suite covers scoring, head-to-head ranking, the Claude request/response handling (with a
stubbed network), and the stores running against the in-memory backend.

## Project layout

```
Config/                 Build settings (Supabase URL/key, Claude model, optional secrets)
Sonder/
  SonderApp.swift       App entry point and root view
  Config.swift          Reads configuration from Info.plist
  Auth/                 AuthStore + welcome / sign-in / sign-up screen
  Stores/               AppStore (cities, profile, feed, photos), SocialStore, Toaster
  Models/               City, ratings, rating draft + insertion search, profile, social types
  Services/
    Backend.swift           Protocol the app talks to
    SupabaseBackend.swift   Production implementation (Auth, PostgREST, Storage)
    InMemoryBackend.swift   Demo mode, previews and tests
    ScoringEngine.swift     Scores, on-device summaries, taste profile, recommendations
    ClaudeService.swift     Claude Messages API (structured JSON output)
    ...                     City/place search, photo metadata, image pipeline, caches
  Data/                 Curated cities, recommendation catalogue, demo data (debug only)
  Theme/                Colours (light + dark), Georgia typography, shared styles
  Views/                Tabs, city flow, map, social, settings, shared components
SonderTests/            Unit tests
supabase/schema.sql     Database schema and policies
project.yml             XcodeGen spec (run `xcodegen generate` after editing)
```

## Before shipping to the App Store

- Set your team and a unique bundle identifier (currently `com.sonder.app`).
- Replace the placeholder app icon if you have final artwork.
- Add a privacy policy and terms URL, and link them from Settings.
- Review `Sonder/Resources/PrivacyInfo.xcprivacy` against what you actually collect.
- Decide how the Anthropic key is delivered (see the note above).
