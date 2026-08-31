# Form answers (his voice, paste-ready)

**Repo (public):** https://github.com/duggsha/persona-trial
New code is one file: Packages/PersonaUI/Sources/PersonaUI/DecisionDeck.swift

**What I did / anything to know:**

I redesigned the cards by what the user has to DO, not what the notification
is. The old feed put a sign-in code, Sarah waiting on an answer, and a flight
change in the same card with the context cut off and no actions. Now there are
three card types. Asks lead with the question, never truncate context, show
stakes as counted precedent (low stakes = you've approved this shape before,
not "it seems small"), and carry the draft plus both actions on the card.
Under approve theres a stronger yes, an always rule, and picking it approves
the current one too. The code card IS the action - whole card copies it and it
visibly expires. Receipts show what ran on its own and name the rule that
authorized it, with undo. Judgment lists every rule as a sentence you can
delete, and deleting one sends its work back to asking.

Approve Sarah with always and ~7 seconds later a Priya reply arrives already
handled under that rule - that's the whole product: it asks less every week,
never silently.

Kept it on your DS tokens, dark first, mono metadata, sharper radii. Your old
feed is still there behind -LEGACY_HOME and I left the CARD_GRAMMAR experiment
untouched.
