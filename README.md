# Persona — Home Screen Design Trial

A running iOS app that renders **one screen**: the Persona home feed. It is the
real shipping SwiftUI code, not a remake — the same header, the same card views,
the same composer, laid out to the same numbers.

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
  MockHomeData.swift      every word on screen
Packages/
  PersonaCore/            data models
  PersonaDesign/          design tokens, palette, glass, assets
  PersonaService/         local-only stores (no network layer)
  PersonaUI/              the screen: header, card feed, composer
```

To change the copy, the cards, the greeting or the persona's name, edit
`App/MockHomeData.swift`. Nothing else reads content from anywhere.

## What works, and what doesn't

The screen is fully interactive. Scrolling, card expand and collapse,
swipe-to-dismiss with its undo toast, the long-press menu, the attach menu's
bloom, keyboard handling and every animation are the real thing.

What's deliberately inert is anything that would have reached a server:

| Gesture | What happens |
| --- | --- |
| Send | Clears the draft. Nothing is sent. |
| Hold to talk | Records, then discards the clip. |
| A card's action button | Reports failure — there is nothing behind it. |
| Pull to refresh | Spins. The deck is fixed. |

## How it was made

The app was ported from the production tree and then reduced to what draws this
one screen. Roughly 85% of the UI package and 95% of the service package were
removed, along with every third-party dependency.

`PersonaService` is a rewrite rather than a trimming: in the real app it is the
network layer, and here it is ~1,000 lines of observable stores holding local
state. There is no HTTP client, no session, no route and no credential in it.

A handful of surfaces that live on this screen in the real app were cut with the
backend they depend on, and are noted in the code where they were: the live-ride
tracker, the sign-in and payment park cards, the empty-deck "connect an app"
panel, the mail-compose and reminder sheets, and the card's chat sheet. The Up
Next meeting hero and the task dock are absent because they are switched off in
the shipping app too.

## One network call

Contact and brand avatars are still fetched from third-party image CDNs
(Gravatar, logo.dev, favicons) — the same path the real app uses. It is not the
Persona backend, and with no network the cards fall back to monograms and SF
Symbols. Everything else is local.
