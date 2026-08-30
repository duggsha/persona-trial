# Persona — Design Trial

A running iOS app that renders **two screens**: the Persona home feed and the
chat transcript, paged between exactly as the app does. It is the real shipping
SwiftUI code, not a remake — the same header, the same card views, the same
bubbles, the same composer, laid out to the same numbers.

It has no backend. Nothing it shows was fetched, and nothing it does is sent.

## Running it

```
xcodegen generate
open PersonaDesignTrial.xcodeproj
```

Build to any iOS 18+ simulator. There are no third-party dependencies to
resolve, no signing to configure and no credentials to supply — a clone builds
offline.

## What's here

```
App/                    the whole trial-specific app (3 files)
  PersonaTrialApp.swift   entry point; injects the four seeded stores
  TrialEnvironment.swift  composition root
  MockHomeData.swift      every word on screen — the feed AND the transcript
Packages/
  PersonaCore/            data models
  PersonaDesign/          design tokens, palette, glass, assets
  PersonaService/         local-only stores (no network layer)
  PersonaUI/              the screens: header, card feed, transcript, composer
```

To change the copy, the cards, the messages, the greeting or the persona's
name, edit `App/MockHomeData.swift`. Nothing else reads content from anywhere.

## Getting between the two pages

Swipe left and right, or tap the house / speech-bubble toggle in the header —
both drive the same pager, with the composer staying put across the transition
because it is one shared bar.

## What works, and what doesn't

Both screens are fully interactive. Paging, scrolling, card expand and collapse,
swipe-to-dismiss with its undo toast, the long-press menu, the attach menu's
bloom, the transcript's swipe-to-reveal timestamps and jump-to-latest chevron,
keyboard handling and every animation are the real thing.

What's deliberately inert is anything that would have reached a server:

| Gesture | What happens |
| --- | --- |
| Send | Clears the draft. Nothing is sent. |
| Hold to talk | Records, then discards the clip. |
| A card's action button | Reports failure — there is nothing behind it. |
| Pull to refresh | Spins. The deck is fixed. |

## How it was made

The app was ported from the production tree and then reduced to what draws these
two screens. Roughly 80% of the UI package and 95% of the service package were
removed, along with every third-party dependency.

`PersonaService` is a rewrite rather than a trimming: in the real app it is the
network layer, and here it is ~1,000 lines of observable stores holding local
state. There is no HTTP client, no session, no route and no credential in it.

A handful of surfaces that live on these screens in the real app were cut with
the backend they depend on, and are noted in the code where they were: the
live-ride tracker, the sign-in and payment park cards, the empty-deck "connect an
app" panel, the mail-compose and reminder sheets, the card's chat sheet, and the
transcript's rich inline cards (a ride, an order, a link preview — every one of
them a live surface). The Up Next meeting hero and the task dock are absent
because they are switched off in the shipping app too.

## One network call

Contact and brand avatars are still fetched from third-party image CDNs
(Gravatar, logo.dev, favicons) — the same path the real app uses. It is not the
Persona backend, and with no network the cards fall back to monograms and SF
Symbols. Everything else is local.
