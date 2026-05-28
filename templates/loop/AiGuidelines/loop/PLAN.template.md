# PLAN — <goal>

> Seeded by `start-loop.sh` from the human's goal. The orchestrator tailors the milestones and
> items below to the actual `<goal>`. Each item is **one** independently verifiable change, tagged
> with the reviewer(s) who should critique it. Work the top unchecked item only; append new
> follow-ups to the bottom; never check a box on a red build.
>
> Reviewer tags: `onboarding`, `paywall`, `ui-ux`, `qa`.

**North-star:** subscription free→paid AND credit-pack purchase conversion (ethical means only).

## M1 — Onboarding activation
- [ ] Audit the first-run flow and choose the stronger `OnBoardingScreen` variation (compare
      `OnBoardingScreenVariation1` vs `OnBoardingScreenVariation2`, pick one, justify in decisions) `[onboarding, ui-ux]`
- [ ] Surface core value before any signup/permission ask (value-first ordering in onboarding) `[onboarding, paywall]`
- [ ] Reduce permission-prompt friction: request only at point-of-need, with rationale `[onboarding, qa]`
- [ ] Tighten time-to-first-value: cut steps between launch and the first useful action `[onboarding, ui-ux]`

## M2 — Paywall conversion
- [ ] Review paywall timing/placement — show after value is demonstrated, not before `[paywall, ui-ux]`
- [ ] Clarify trial framing and the primary CTA on `SubscriptionPaywallScreen` `[paywall]`
- [ ] Improve credit-pack presentation and verify PPP / price correctness on `CreditPackPaywallScreen` `[paywall, qa]`
- [ ] Make value explicit before the ask (benefits/social proof copy, honest — no fake scarcity) `[paywall, ui-ux]`

## M3 — UX & quality hardening
- [ ] Tap-target + accessibility pass (contrast, labels, dynamic type) on changed screens `[ui-ux]`
- [ ] Cover error / offline / empty states for changed flows `[qa]`
- [ ] Add/refresh Roborazzi snapshot coverage for changed screens (record deliberately) `[qa, ui-ux]`

## Follow-ups (append below as discovered)
