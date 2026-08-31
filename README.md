# Iris — the decision deck

Design trial for the Persona founding design engineer role. Base is the real
Iris home screen ([tanaysingh1/persona-design-trial](https://github.com/tanaysingh1/persona-design-trial));
everything described below is the redesign, live in this repo.

## The read

The brief said: make the actions obvious, make the context clear, make it
beautiful — Jarvis, not soft.

Looking at the shipped feed, the real problem wasn't styling. A sign-in code,
a person waiting on an answer, and a flight that already moved were all
wearing the same card: icon, two truncated lines, a blue dot, a chevron. No
card said what you could do with it, and the one clause that mattered was cut
mid-sentence.

**Different kinds of things get different cards, and every card carries its
actions.** That's the whole redesign.

## The grammar

**ASK** — the agent needs a yes. The ask is the headline, the context never
truncates, and the stakes are printed, not implied: `HIGH STAKES · first send
as you`, `LOW STAKES · 3 approvals · reversible`. Low stakes doesn't mean the
action looks small — it means **precedent exists**. The draft it wants to send
sits on the card, tap to edit. Decline and approve are right there; under the
approve chevron sits the stronger yes — an **always-rule** — and saying always
approves the current one too. Approving streams the agent's actual steps, then
the card seals and files itself under HANDLED.

**UTILITY** — the card is the action. The code is set in 34pt mono, the whole
card copies it, and it visibly expires (a draining hairline and a countdown —
a dead code is a lie, so it dims when it dies).

**RECEIPT** — the agent already acted where it had standing. One line of what
happened, the rule that authorised it (`RULE · KEEP TRAVEL PLANS CURRENT`),
and a live **Undo**.

**JUDGMENT** — every standing permission, readable as one sentence, counted
(`USED 7×`), and deletable. Delete a rule and anything it authorised returns
to the feed as a question. Nobody should hold a permission they can't read.

The loop this closes: approve → it runs → receipt. Say always → the current
one runs **and** later work of the same shape arrives already handled, tagged
with the rule, undo intact. That's how trust actually graduates — the feed
asks less every week, and never silently.

## The look

Dark-first (an operator's instrument commits), ink on near-black, hairlines
instead of shadows, one accent (the filled action), SF Mono for every piece of
metadata, radii at 14/8/6 continuous — deliberately sharper than the shipped
28pt pills. Built entirely on the app's own `DS` tokens; light mode still
resolves through them.

## Run it

```
open PersonaDesignTrial.xcodeproj
```

iOS 18+ simulator, no backend, no signing. Launch args:

- *(none)* — the redesign
- `-LEGACY_HOME` — the shipped feed this started from
- `-CARD_GRAMMAR` — the team's earlier grammar experiment, untouched

Everything works: approve/decline, edit the draft, always-rules, the
7-second graduation card, tap-to-copy (check the clipboard), expiry, undo,
and rule deletion re-opening the ask.

New code is one file: `Packages/PersonaUI/Sources/PersonaUI/DecisionDeck.swift`.
Screenshots in `shots/`.
