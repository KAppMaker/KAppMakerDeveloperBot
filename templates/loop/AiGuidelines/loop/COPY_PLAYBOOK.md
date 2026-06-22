# Copy playbook — voice, microcopy & killing AI-slop text

The shared reference for every agent that writes or reviews user-facing words: the `orchestrator`
(at build time) and the `onboarding-specialist`, `paywall-conversion-specialist`,
`growth-virality-specialist`, and `delight-specialist` (at review time). It is the **writing lens**:
how the app should sound, the slop to never ship, and the microcopy patterns that convert. This app's
specific brand voice lives in `AiGuidelines/project/voice.md` (tone, vocabulary, example phrasings);
read that for *who this app sounds like*, read this for the universal craft and the review rubric.

**North-star:** words are the product's first impression and a top conversion lever. Onboarding copy
in particular has seconds to make the user feel "this gets me." Generic, robotic, or jargon-filled
text reads as low-effort and leaks trust (and conversion) on every screen. Every rule below serves
"the user believes a real, thoughtful person built this for them."

> **Why app copy reads as AI-written.** Almost always the same tells: the **em-dash habit**, the
> "it's not just X, it's Y" cadence, a stock vocabulary of hype words (unlock, elevate, seamless,
> effortless), feature-talk instead of benefit-talk, and vague headlines. Strip those and the text
> instantly sounds human. The fix is a banned list applied without exception (§2), not "try to write
> better."

---

## 1. Voice and tone

- **Talk to one person, as a person.** Second person ("you", "your"), active voice, plain words.
  Write the way you would explain it to a friend, not the way a brochure announces it.
- **Benefit before feature.** Say what the user gets, not what the app does. "Know what is in your
  food in 2 seconds", not "Powered by an advanced ingredient-analysis engine".
- **Speak to the goal.** Reflect the goal the user gave in onboarding back to them (ties to
  CONVERSION_PLAYBOOK §2.1). Personal beats generic.
- **Concrete over abstract.** Real numbers, real outcomes, real nouns. Abstractions ("optimize your
  potential") say nothing.
- **Confident, not hypey.** State the value plainly and stop. Confidence is calm; hype is loud.
- **Adapt to `voice.md`.** The rules here are universal; the personality (playful, clinical, warm,
  bold) comes from the app's `voice.md`. If there is tension, the app's voice wins on tone, this
  playbook wins on mechanics (§2, §5).

---

## 2. The AI-slop banned list (apply without exception in UI copy)

These are the recognizable tells of machine-written text. Any one of them in shipped UI copy is a
defect.

- **No em-dashes or en-dashes (`—`, `–`) in UI copy.** This is the single biggest tell. Rewrite with
  a comma, a period (two short sentences), parentheses, or a colon. (The user explicitly dislikes
  "long hyphens", so eliminate them from the app, not just soften them.)
- **No "it's not just X, it's Y" / "It's not A. It's B." construction.** Overused AI cadence. Just
  say what it is.
- **No hype vocabulary:** unlock, elevate, supercharge, seamless, effortless, unleash, empower,
  revolutionize, game-changing, cutting-edge, next-level, robust, leverage, harness, dive in,
  delve, "in today's world / fast-paced world", "whether you are a … or a …", "take it to the next
  level", "your journey", "elevate your experience". Replace with the plain verb or cut.
- **No filler openers:** "Simply", "Just", "Easily", "Effortlessly" stacked on every sentence;
  "We are excited to…", "Get ready to…".
- **No vague abstractions as headlines:** "Achieve your goals", "Unlock your potential",
  "Experience the difference". Say the specific thing.
- **No emoji as bullets or as a substitute for words** (icons belong to the design system, not the
  copy). An occasional emoji inside a friendly line can fit some `voice.md`; rows of 🚀✨🔥 do not.
- **No Title Case On Every Word**, no ALL-CAPS shouting, no exclamation-mark spam (one `!` is plenty,
  usually zero).
- **No hedging:** "might", "maybe", "should", "we think". If it is true, say it.

---

## 3. Onboarding copy (the first impression)

Onboarding has the highest copy stakes. The job is to make the user feel understood and pulled
forward.

- **Screen 1 is a hook, not a tour.** Lead with the user's problem or the transformation they want,
  in their words. Make them feel "yes, that's me" before anything else.
- **One idea per screen.** A short, specific headline plus at most one or two supporting lines. Mobile
  readers skim; long paragraphs get skipped.
- **Problem then transformation.** Name the pain, then show the better state the app delivers. Keep
  it concrete and personal.
- **Earn each tap.** Every screen should add value or move the user toward their goal. If a screen
  only says "Welcome", cut or merge it.
- **Reflect the captured goal later.** What you ask in onboarding should reappear (on the plan
  preview and the paywall). Copy that remembers the user converts.
- **Honest and warm at the ask.** When you transition to signup or paywall, keep the same voice. No
  sudden salesy register shift.

---

## 4. Microcopy patterns

- **Buttons: verb-first and specific.** "Start my plan", "Scan a label", "Create my first workout",
  not "Continue", "Submit", "Next", "Get started" everywhere. The label should say what happens.
  One primary action per screen.
- **Headlines: a benefit in about six words.** Specific and scannable. If it could headline any app,
  rewrite it.
- **Body: one idea, one or two lines.** Cut every word that does not change the meaning.
- **Permission priming: state the user benefit first.** "Turn on notifications so we can remind you
  before your streak resets", not "Allow notifications". Never open with the bare system reason.
- **Empty states: point to the next action, with a little warmth.** "No scans yet. Point your camera
  at any label to start." Never a blank screen or a flat "No data".
- **Errors: plain, specific, no blame, no jargon.** Say what happened and how to fix it. "We could
  not reach the server. Check your connection and try again." Never a raw code or stack trace in the
  user's face.
- **Loading: reassure, do not narrate the tech.** "Building your plan…" beats "Initializing model".
- **Paywall copy: honest and value-framed.** Lead with what the user gets; state trial terms plainly
  ("3 days free, then $39.99/year. Cancel anytime."). See CONVERSION_PLAYBOOK §3 for offer structure.

---

## 5. Formatting and mechanics

- **Sentence case** for headings, buttons, and labels (not Title Case).
- **Real punctuation, no em-dashes** (§2). Short sentences over long ones joined by dashes.
- **Numerals for numbers** ("2 seconds", "5 workouts"), they scan faster than spelled-out words.
- **Expand or avoid acronyms and jargon.** If a normal user would not know the term, do not use it.
- **One name per concept.** Pick a term and keep it everywhere (do not call it "plan" here and
  "program" there).
- **Localization-friendly.** Avoid idioms and puns that will not translate; keep strings whole
  (no sentence built by string concatenation).
- **Length aware.** Copy must survive dynamic type and the longest supported language without
  clipping. Shorter is safer and usually better.

---

## 6. Anti-slop checklist (run this every copy review)

Flag any that are true:

- [ ] An em-dash or en-dash (`—` / `–`) appears in user-facing copy (§2).
- [ ] A banned hype word or the "not just X, it's Y" construction appears (§2).
- [ ] Jargon, an unexplained acronym, or tech-speak the user would not use (§5).
- [ ] A headline is vague or could belong to any app (§3, §4).
- [ ] Copy describes a feature instead of the user's benefit (§1).
- [ ] A button label is generic ("Continue" / "Submit" / "Next") where a specific verb fits (§4).
- [ ] Title Case on everything, ALL-CAPS, or exclamation spam (§2, §5).
- [ ] An empty/error state is blank, blames the user, or shows a raw code (§4).
- [ ] Onboarding screen 1 does not hook (no problem/transformation in the user's words) (§3).
- [ ] Inconsistent terminology for the same concept across screens (§5).

---

## 7. Review rubric (copy-writing reviewers apply this)

For each reviewed change, write findings tagged by severity:

- **blocker** — copy that misleads, makes a false claim, or breaks trust (deceptive paywall wording,
  dishonest trial terms). Tie to ethics: honest means only.
- **major** — a clear AI-slop tell in shipped copy: an em-dash, a banned hype word, a feature-not-
  benefit headline, a vague hook, jargon a user would not understand. These read as low quality, so
  they are `major`, not nits.
- **minor** — weaker wording, generic button label, suboptimal length, mild inconsistency.
- **nit** — small polish (a tighter synonym, punctuation).

Tie every finding to a section above, cite `file:line`, and give the **rewritten string** as the
suggested edit (not just "make it better"). Verdict: `ship` / `fix-first` / `block`.

---

## Sources & credit

Distilled from established content-design guidance, adapt to this app's `voice.md`, do not
cargo-cult:
- **Apple Human Interface Guidelines, Writing** — clear, benefit-first, consistent terminology:
  [developer.apple.com/design/human-interface-guidelines/writing](https://developer.apple.com/design/human-interface-guidelines/writing).
- **Material Design, Writing** — concise, useful, sentence case, plain error messages:
  [m3.material.io/foundations/content-design/style-guide](https://m3.material.io/foundations/content-design/style-guide).
- General content-style practice (Mailchimp Content Style Guide, Shopify Polaris content guidelines)
  for voice, microcopy, and accessible plain language.
