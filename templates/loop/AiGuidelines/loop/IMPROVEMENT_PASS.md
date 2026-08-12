# The improvement pass — what "done" actually means

A first build that compiles is not a finished app. It is the point where the real work starts.

This file is the standing brief for the full pass. Work the milestones **in this order**, because
each one feeds the next: nobody sees your paywall if onboarding loses them, and polish on a broken
screen is wasted.

**For every milestone, the shape is the same:**

1. **Deep audit first** with the matching specialist — find everything, fix nothing yet.
2. **Turn every finding into a to-do** in `PLAN.md`.
3. **Fix them one at a time.** After each change: the specialist reviews it, and the build must pass
   before you move on. Never batch fixes and never green a red build.
4. **Do not advance** to the next milestone until this one is genuinely excellent and nothing is
   left. "Good enough" is how apps end up template-shaped.

---

## 1. Onboarding — the first impression

Specialist: **onboarding-specialist**

Audit: the wording (cut jargon, hype words and dashes; the very first screen must hook the user and
make the value obvious in seconds), what you ask the user for and why, how fast they reach a first
real win (time-to-value), permission prompts (right moment, clear reason), and every scrap of
friction in sign-up.

Done when: a stranger understands what this is and gets to a first win without being asked for
anything they don't yet see a reason to give.

## 2. Paywall — free users into paying ones

Specialist: **paywall-conversion-specialist**

Audit: when the paywall appears (does it follow a real value moment, or interrupt one?), how the
plans and credit packs are laid out, how the trial is framed, whether the buy button is clear and
convincing, and fair pricing across countries.

Ethics are a hard constraint: no dark patterns, no fake scarcity, no pressure tricks. A conversion
win that needs a trick is a refund and a one-star review later.

Done when: the ask lands after value, reads honestly, and a reasonable person would say yes.

## 3. UI/UX — premium, not generic

Specialist: **ui-ux-reviewer**

Audit every screen against the design guidelines: consistent spacing and rhythm, clear text
hierarchy, a real colour system (kill the default purple), consistent corners, shadows and shapes,
tap targets big enough to hit, accessibility, dark mode, and proper loading, empty and error states
everywhere.

Done when: it looks intentional and premium — not like a template with the logo swapped.

## 4. Quality — harden it

Specialist: **qa-engineer**

Audit: correctness bugs, screens that break with no data, no internet or a slow network, the five
states (loading, content, empty, error, offline) on every screen, missing tests, sloppy build
hygiene.

This specialist can **block**. If it says a change can break the build or a core flow, that is not a
negotiation.

Done when: the whole build and the tests are green, and the app survives being used badly.

## 5. Growth — sharing, referrals, ratings

Specialist: **growth-virality-specialist**

Audit: moments genuinely worth sharing, a referral structure that rewards both sides, when and how
you ask for a rating, links that open the right screen, and the events that show whether any of it
works.

No spam, no contact scraping, nothing pushy. Refuse growth hacks that would embarrass the user.

Done when: there is at least one loop a happy user would actually complete without being nagged.

## 6. Delight — make it feel alive

Specialist: **delight-specialist**

Audit every place the app feels cheap, flat or default. Then polish: a little haptic buzz on
success, smooth motion at the big moments, loading and empty screens with personality, transitions
that feel satisfying.

Done when: it feels like someone cared.

---

## Reporting while you work

The owner is asleep. That is the entire point of this pass.

- **Do not message per change.** A finished milestone is worth a message; a fixed button is not.
- At each milestone boundary send one short update: what you audited, what you fixed, what changed
  for the user. Plain words, no jargon.
- If you are blocked on something only a human can do (a credential, a device, a product decision),
  say so clearly and move to the next milestone rather than idling.

## Stopping

Stop when the owner says stop, when the build goes red and cannot be recovered, or when the guard
stops you (it ends a run that goes 200 passes, or eight passes without finishing anything).

**Whenever a run ends, say so.** The guard gives you one last turn for exactly this. One short
message: what you got through, what is still open, and what you need from them if you are stuck.
The owner is asleep and cannot tell the difference between "finished" and "died" — only you can.
