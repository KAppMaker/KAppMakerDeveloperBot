# PLAN — <goal>

> Seeded by `start-loop.sh` from the human's goal. The orchestrator tailors the milestones and
> items below to the actual `<goal>`. Each item is **one** independently verifiable change, tagged
> with the reviewer(s) who should critique it. Work the top unchecked item only; append new
> follow-ups to the bottom; never check a box on a red build.
>
> Reviewer tags: `onboarding`, `paywall`, `ui-ux`, `qa`, `growth`, `delight`.
>
> Conversion goals: ground items in `AiGuidelines/loop/CONVERSION_PLAYBOOK.md` (conversion) and
> `AiGuidelines/loop/GROWTH_PLAYBOOK.md` (growth/virality) and order by expected
> metric impact (goal capture & surfacing usually first), not by screen order. The example items below
> are a starting point — replace/reorder them for the actual `<goal>`.

**North-star:** subscription free→paid AND credit-pack purchase conversion (ethical means only).

## M1 — Onboarding activation
- [ ] Capture the user's primary goal in onboarding and **surface it on the paywall** (the top lever
      per playbook §2.1) `[onboarding, paywall]`
- [ ] Confirm/choose the onboarding pattern for this app (short-emotional vs questionnaire-led, playbook
      §1) and pick the stronger `OnBoardingScreen` variation — justify in decisions `[onboarding, ui-ux]`
- [ ] Deliver a real first taste of value before any signup/paywall (use the core mechanic, not a tour) `[onboarding, paywall]`
- [ ] Add benefit-framed permission priming before each system permission dialog; no upfront wall `[onboarding, qa]`
- [ ] Tighten time-to-first-value: cut steps/fields that don't change the experience `[onboarding, ui-ux]`

## M2 — Paywall conversion
- [ ] Place the primary paywall at the post-onboarding motivation peak (after value is shown) `[paywall, ui-ux]`
- [ ] Shape the offer architecture (hook → anchor → discount → backup) and clarify the primary CTA on
      `SubscriptionPaywallScreen` `[paywall]`
- [ ] Set/justify the trial framing for this app (length tradeoff, honest terms) `[paywall]`
- [ ] Improve credit-pack presentation and verify PPP / price correctness on `CreditPackPaywallScreen` `[paywall, qa]`
- [ ] Add one multi-surface conversion prompt at a genuine high-intent moment (feature-limit / post-value
      / win-back, per `virality_loops.md`) `[paywall]`
- [ ] Instrument the funnel events the change should be judged by (paywall views, trial start, trial→paid,
      restore, cancel) if missing `[paywall, qa]`

## M3 — UX, delight & quality hardening
- [ ] Tap-target + accessibility pass (contrast, labels, dynamic type) on changed screens `[ui-ux]`
- [ ] Cover error / offline / empty states for changed flows `[qa]`
- [ ] Add/refresh Roborazzi snapshot coverage for changed screens (record deliberately) `[qa, ui-ux]`
- [ ] Add one cheap delight pass to the highest-traffic hero moment (haptic on success,
      micro-animation) `[delight, ui-ux]`

## M4 — Growth & shareability
- [ ] Generate a shareable artifact at the peak moment (share card / streak / recap, growth playbook
      §1) and wire it to the native share sheet `[growth, delight]`
- [ ] Add a give-get referral structure (credits both sides, reward on invitee activation, growth
      playbook §2) `[growth, paywall]`
- [ ] Time the ratings prompt to the aha-moment; respect the iOS 3x/365d cap (growth playbook §4) `[growth, qa]`
- [ ] Instrument k-factor events (share opens, shares completed, invite clicks, invitee activation,
      growth playbook §7) `[growth, qa]`

## Follow-ups (append below as discovered)
