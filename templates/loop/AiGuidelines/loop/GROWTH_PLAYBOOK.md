# Growth playbook — virality, sharing & referrals

The shared reference for the self-improve loop's growth reviewer (`growth-virality-specialist`) and
the `orchestrator`. It is the **growth lens** they apply when planning and reviewing: which
mechanics create compounding distribution, and how to judge a change. The app's own
`AiGuidelines/project/virality_loops.md` holds *this app's* specific strategy — read that for the
product decisions; read this for the principles and the review rubric.

**North-star:** growth work serves subscription free→paid AND credit-pack conversion by compounding
the top of the funnel. The supporting metric is **k-factor** (invites/shares sent per user ×
invite→install conversion) — by **honest means only** (see Ethics).

---

## 1. Shareable artifacts — the cheapest loop

Generate a flattering, lightly-branded artifact at a **peak moment** (achievement unlocked, streak
milestone, a finished result the user is proud of) and hand it straight to the native share sheet.

- **Evidence:** Duolingo redesigned its milestone share cards as premium artifacts (per-platform
  aspect ratios, custom illustrations) and saw a ~5–10x lift in organic sharing — millions of streak
  shares per day. Spotify Wrapped turns plain usage data into a story users *want* to post, and its
  annual drop reactivates churned users at scale.
- **Rules:** the artifact flatters the **user**, not the app; branding is a subtle watermark plus a
  deep link for attribution; generate it client-side at the moment of pride (no extra steps); never
  gate sharing behind the paywall — shares are free distribution.
- **Recap pattern:** a periodic "your month/year in {app}" summary is the same mechanic on a timer;
  it doubles as a win-back surface.

## 2. Referral structure — give-get, in product currency

Reward **both** sides, and pay the reward in the thing the app already meters. For KAppMaker apps
**credits are the natural give-get unit** — a referral reward that doubles as a taste of the
credit-pack economy ladders directly into the north-star.

- **Evidence:** Dropbox's two-sided storage referral (reward = the core product) is the canonical
  loop; Evernote ran tiered points redeemable for free premium months. Give-get ("give 20, get 20")
  keeps acquisition cost predictable; tiers (1 referral → credits, 3 → bigger pack, 10 → a premium
  month) keep advocates sharing.
- **Rules:** reward on the invitee's **activation** (first real action), not mere install — installs
  are gameable; cap total rewards; make the share message editable, never auto-sent.

## 3. Time-pressure & social mechanics — fit-dependent

Synchronized or scarce moments (BeReal's 2-minute window, Gas's hourly friend polls, Locket's
home-screen widget between close friends) create urgency and ritual — but they only work where the
social loop **is** the product. Flag bolt-on copies of these mechanics in single-player apps as
likely wasted effort; recommend artifact + referral loops (§1–2) instead.

## 4. Ratings-prompt timing

The store rating is a growth surface: volume and recency move store ranking and listing conversion.

- Ask **right after a clear success** (task completed, streak hit, result delivered) — the
  aha-moment. Field data (e.g. the 7 Minute Workout teardown) shows aha-moment prompts beat
  onboarding prompts on both volume and average rating.
- **Never** prompt on first launch, during onboarding, mid-task, or after an error.
- iOS shows the system prompt at most **3 times per 365 days** per user — every ask must be spent at
  a high point. Android's in-app review API has an undocumented quota; same discipline applies.
- A lightweight "Enjoying {app}?" pre-prompt before spending the system dialog is acceptable **only
  if both paths are honest**: a negative answer routes to a feedback form, and unhappy users are
  never tricked or suppressed. Never incentivize, gate, or filter ratings.

## 5. Funnel consistency — ad/creator hook → onboarding → paywall

The promise that won the install must persist through onboarding to the offer; inconsistency leaks
conversion (CONVERSION_PLAYBOOK §2.4 is the same principle from the conversion side).

- **Evidence:** Cal AI paired a TikTok creator flywheel (hundreds of creators on retainer) with
  relentless funnel experimentation — 123 paywall experiments across 46 trigger points, +31%
  trial→paid while revenue 3x'd in 10 months. The lesson for the loop: the in-app funnel must be
  instrumented and iterable so creative wins outside the app aren't wasted inside it.
- The onboarding quiz itself can be a growth surface: a personalized result is a shareable artifact.

## 6. Word-of-mouth via craft

Polish people screenshot and talk about is distribution: Flighty's Live Activities and obsessive
detail won an Apple Design Award and most of its press; Yuka grew to ~73M users on word-of-mouth
with no ad spend; Partiful's playful invite pages make every event an ad. This lever is the
`delight-specialist`'s mandate — the growth reviewer flags **missed shareable moments**; the delight
reviewer makes the moment worth sharing.

## 7. Measure the right things

A growth change is judged by the loop's numbers, not opinion. Decompose k-factor and instrument each
step: **share-surface impressions → share-sheet opens → shares completed → link clicks → installs →
invitee activation**, plus referral attribution and deep-link landing success (a link that lands on
a cold launch instead of the shared content kills the loop). If a growth change isn't measurable,
the first finding is "add the event."

---

## 8. Ethics — hard line

Grow **only** by honest means. **Flag and refuse**: contact-book scraping or auto-invites, spam or
pre-filled bulk messages, posting on the user's behalf without an explicit action, incentivized or
gated ratings, fake social proof ("12 friends joined!"), and growth mechanics that leak private data
(shared artifacts must never expose contacts, location, or private content by default) — even if it
would lift k-factor. If the item asks for one of these, verdict `block` and explain.

---

## 9. Review rubric (the growth reviewer applies this)

For each reviewed change, write findings tagged by severity:
- **blocker** — ships a spammy/deceptive mechanic, shares private data, posts without consent, or
  games ratings.
- **major** — misses a top lever (peak moment with no share artifact, referral with no activation
  gate or no measurement, ratings prompt mistimed or spent on launch, deep link landing cold).
- **minor** — weaker share copy/placement, artifact that brands the app more than it flatters the
  user, suboptimal reward sizing.
- **nit** — polish.

Tie every finding to a lever above and the loop metric it moves (share rate, invite conversion,
rating volume), cite `file:line`, and give a concrete suggested edit. Verdict: `ship` / `fix-first`
/ `block`.

---

## Sources & credit

Distilled from public growth teardowns — adapt, don't cargo-cult:
- Cal AI paywall/funnel experimentation — [Superwall case study](https://superwall.com/case-studies/cal-ai);
  TikTok creator flywheel — [Plutus teardown](https://growwithplutus.com/blog/cal-ai-app-tiktok-strategy).
- Duolingo share cards & streak mechanics — [Trophy: building a Wrapped feature](https://trophy.so/blog/how-to-build-wrapped-feature),
  [Deconstructor of Fun: streaks](https://duolingo.deconstructoroffun.com/mechanics/streaks).
- Referral program structures — [RevenueCat: referral programs for mobile apps](https://www.revenuecat.com/blog/growth/how-to-build-a-referral-program-for-mobile-apps/),
  [Tapp: 15+ referral teardowns](https://www.tapp.so/blog/mobile-app-referral-program-examples/).
- Ratings-prompt timing — [Appbot: prompt early or wait](https://appbot.co/blog/prompting-for-ratings-prompt-early-or-wait/).
- Word-of-mouth via craft — [Apple Design Awards (Flighty)](https://developer.apple.com/design/awards/2023/),
  [Yuka founder on organic growth](https://www.uschamber.com/co/good-company/the-leap/yuka-app-organic-growth),
  [Sacra: Partiful](https://sacra.com/c/partiful/).
