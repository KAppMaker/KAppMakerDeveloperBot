# Conversion playbook — onboarding & paywall

The shared reference for the self-improve loop's money specialists (`onboarding-specialist`,
`paywall-conversion-specialist`) and the `orchestrator`. It is the **conversion lens** they apply
when planning and reviewing: what "great" looks like, which levers move the metric, and how to judge
a change. The app's own `AiGuidelines/project/{onboarding,paywall,virality_loops}.md` hold *this
app's* specific strategy — read those for the product decisions; read this for the principles and the
review rubric.

**North-star:** subscription free→paid conversion AND credit-pack purchase conversion. Every lever
below ladders up to activation → trial start → paid — by **honest means only** (see Ethics).

---

## 1. Onboarding pattern toolkit — pick by context, don't default

There is no single right length. Choose the pattern that fits the app, the personalization payoff,
and how warm the incoming traffic is. The job of onboarding is to **capture intent, build
commitment, and deliver a first taste of value** before the ask — then place the paywall at the
motivation peak.

| Pattern | Shape | Fits when |
|---|---|---|
| **Short emotional** (3–4 screens) | hook → problem → transformation → soft offer | Simple value prop, warm traffic that already knows what it wants, utility apps where time-to-value is the whole game. (This is the KAppMaker default `OnBoardingScreen` shape.) |
| **Questionnaire / quiz-led** (9–20 screens) | promise → trust → **goal capture** → profile → micro-progress → personalized plan → **demo / first taste** → recap → paywall | Personalization meaningfully changes the experience (health, finance, learning, AI tools), colder paid traffic that needs investment built, apps where a tailored plan is the hook. |

**Decision guide.** More personalization payoff + colder traffic → longer, quiz-led. Self-evident
value + warm traffic → shorter. When unsure, the highest-leverage move is rarely "more screens" — it
is **capturing the user's goal and surfacing it on the paywall** (see §2). Recommend a pattern *with
a reason tied to this app*, not a dogma.

Reference frameworks (toolkit, not mandates):
- **9-step:** promise → trust/social proof → goal → profile/constraints → micro-progress → plan
  preview → first taste of value → value recap → paywall.
- **14-screen psychological:** welcome → goal → pain points → social proof → self-identification →
  personalized solution → comparison → preferences → **permission priming** → processing →
  **app demo (use the real mechanic, not a tour)** → value delivery/share → account gate → paywall.

---

## 2. High-leverage principles (rank work by these)

1. **Capture the goal, then surface it on the paywall.** Ask the user's goal early; echo it back at
   the ask ("To help you *{goal}*, your plan includes…"). Even a single goal→paywall string match
   tends to beat most layout experiments. This is usually the #1 lever — prioritize it.
2. **Value before the ask.** Show the core benefit — ideally let the user *use the real mechanic
   once* (a real sample/output), not a passive tour — before any paywall or hard permission.
3. **Benefit-framed permission priming.** Precede every system permission dialog with a screen that
   explains the benefit ("Allow notifications so we can remind you of your streak"). Primed prompts
   convert far better than cold system dialogs; never open with a permission wall.
4. **Consistent message ad → onboarding → paywall.** The promise that won the install must persist
   through onboarding to the offer. Inconsistency leaks conversion.
5. **Micro-progress & commitment.** Step indicators ("Step 2 of 5"), light positive feedback, and a
   personalized plan preview make the flow feel finite and create psychological investment.
6. **Cut friction on the ask, not the value.** No forced account creation before value; offer a
   guest/skip path; only collect fields that change the experience.

---

## 3. Paywall architecture

- **Placement:** the post-onboarding motivation peak converts a large share of all trial starts —
  show the primary paywall there, after value is demonstrated, not as a cold wall on launch.
- **Offer architecture:** hook (free trial / risk-free framing) → **anchor** (monthly price) →
  **discount** (annual presented against the monthly anchor, with the savings made explicit) →
  **backup** (a smaller fallback offer if the user declines, where appropriate).
- **Trial framing — a real tradeoff, not a rule.** Short trials (3-day) create urgency and are common
  for impulse/utility apps; longer trials (≈17–32 days) tend to show higher trial→paid in the data
  for considered purchases. Recommend per app and **state the trial terms honestly** ("3 days free,
  then $X/yr. Cancel anytime.").
- **CTA clarity:** one primary action, benefit-oriented label (not a bare "Subscribe"), no decision
  paralysis. Legal/renewal terms visible but not shouting. (For voice and microcopy — labels,
  headlines, honest trial wording, no em-dashes or hype words — see `COPY_PLAYBOOK.md`.)
- **Credit-packs:** clear per-unit value, sensible (honest) anchoring — highlight the genuine
  best-value pack, never a fake one; correct PPP (purchasing-power) pricing per region.
- **Subscription vs credit-pack:** decide which the first paywall leads with and why (see the app's
  `paywall.md`); don't present both with equal weight if one is the primary model.

---

## 4. Multi-surface monetization

One onboarding paywall is the floor, not the ceiling. High-intent moments across the lifecycle
justify their own tailored prompts: hitting a feature/usage limit, completing a valuable action, a
streak/achievement, or returning after lapse (win-back). See the app's `virality_loops.md` for the
share/referral and re-engagement surfaces. Each added surface should be tied to a genuine
high-intent moment — not nagging.

---

## 5. Measure the right things

A conversion change is judged by behavior, not opinion. The events to look for (and to flag as
missing if they aren't instrumented): onboarding **completion rate** and **per-step drop-off**,
**day-0 paywall views**, **trial starts**, **trial→paid**, **restore**, and **cancel**. If a change
claims a conversion lift but the funnel isn't measurable, the first recommendation is to add the
event.

---

## 6. Ethics — hard line

Optimize **only** by honest means: clear value, fair trial framing, transparent pricing, easy
cancellation. **Refuse** fake scarcity/countdowns, deceptive or buried cancel flows, pre-checked
upsells, misleading "free" labels, and confusing price anchoring — even if it would lift the metric.
If a requested change crosses this line, return `block` and explain instead of implementing it.

---

## 7. Review rubric (specialists apply this)

For each reviewed change, write findings tagged by severity:
- **blocker** — ships a dark pattern, breaks the funnel, or makes the ask before any value.
- **major** — misses a top lever (no goal capture/surfacing, paywall mistimed, cold permission wall,
  unclear primary CTA, untrackable funnel).
- **minor** — weaker copy, suboptimal ordering, anchoring could be clearer.
- **nit** — polish.

Tie every finding to a lever above and to the conversion goal it serves, cite `file:line`, and give a
concrete suggested edit. Verdict: `ship` / `fix-first` / `block`.

---

## Sources & credit

Distilled from public conversion teardowns and frameworks — adapt, don't cargo-cult:
- Cal AI growth/paywall experimentation — [Superwall case study](https://superwall.com/case-studies/cal-ai).
- [RevenueCat — guide to mobile paywalls](https://www.revenuecat.com/blog/growth/guide-to-mobile-paywalls-subscription-apps/)
  and [Adapty onboarding best practices](https://adapty.io/blog/how-to-fix-your-onboarding-flow/).
- Questionnaire-led onboarding (14-screen framework, modeled on Mob/Noom/Headspace/Duolingo) —
  [Adam Lyttle's open Claude skill](https://github.com/adamlyttleapps/claude-skill-app-onboarding-questionnaire).
- 9-step onboarding→paywall breakdown — [PaywallPro](https://dev.to/paywallpro/complete-onboarding-breakdown-9-steps-from-first-screen-to-paywall-2j7).
