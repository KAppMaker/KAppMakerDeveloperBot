# Engagement playbook — the inward loop

Why users come back tomorrow. Growth (GROWTH_PLAYBOOK.md) is the outward loop — users bringing
users; this is the inward one — the reward and progress system that turns a first session into a
habit. The two meet at peak moments: what this playbook celebrates is often what that one shares.

Owned by `engagement-specialist` at review time; the orchestrator builds from it whenever an item
is tagged `engagement`.

## 1. Celebrate real achievement — and nothing else

- Map the app's **peak moments**: first success (the aha), completions, milestone marks, streak
  records, comebacks. These get celebrated. Routine actions get at most a subtle acknowledgment.
- A celebration is choreography, not a toast: motion + haptic + copy landing together, sized to the
  achievement (first-ever success > weekly milestone > daily tick).
- Budget it. An app that fires confetti at everything teaches the user that its praise is noise.
  One rule of thumb: if it can happen five times a minute, it is not a celebration.
- The **first celebration must land in session one** — it teaches the user that progress here
  feels good. Design onboarding so a real (small) achievement occurs before the first ask.

## 2. Streaks — motivate, never punish

- A streak is a promise the app helps the user keep: show it before it is at risk, not after it is
  lost.
- **Forgiveness is a feature**: grace days, streak freezes, or repair windows. A streak lost to one
  bad day converts loss-aversion into resentment; a repairable streak converts it into a return.
- The comeback moment matters more than the loss: "start a new run" framing, and (if a mascot
  exists) it is *happy to see you*, never disappointed in you.
- Streaks fit habit-shaped apps. A tool used twice a month should not have one — check the PRD
  before endorsing.

## 3. Milestones — the visible ladder

- Always one next milestone visible, plausibly reachable, and meaningfully spaced (progress rings,
  levels, badge tiers — pick one system, not three).
- Front-load the ladder: milestone 1 in session one, milestone 2 within the first week. Spacing can
  stretch as investment grows.
- A milestone can pay in **product currency** (credits, unlocks) — that is also the referral
  reward currency (GROWTH_PLAYBOOK §2); keep the economy coherent.
- Completed milestones are shareable-artifact candidates (GROWTH_PLAYBOOK §1) — instrument the
  handoff.

## 4. Mascot / companion — a decision, not a default

A persistent character that reacts to the user's progress (the tamagotchi pattern) is the strongest
engagement device on this list **when it fits** — and clutter when it does not.

- **Fit test first**: audience tolerates personality? App is habit-shaped, with progress worth
  reacting to? Voice supports it (`voice.md`)? A B2B utility fails this test; a language-learning,
  habit, fitness or kids app usually passes.
- **State model**: small and legible — `idle / happy / celebrating / missing-you` is enough. Every
  state maps to real user data (progress, streak state, absence); a mascot that emotes randomly is
  wallpaper.
- **Care mechanic (optional, the tamagotchi step)**: user actions visibly feed/grow the companion —
  its wellbeing mirrors the user's own consistency. If used: absence makes it *miss* the user, never
  suffer. Guilt is the ethics line (§6).
- **Placement**: where it earns its keep — empty states, the streak/progress screen, onboarding, the
  celebration itself. Not floating over every screen.
- **Art**: generated through the app's existing image tooling in the app's visual style, one
  consistent character across all states. Never stock or clip-art.

## 5. Retention cadence — reminders that help

- Every reminder ties to a **value moment the user actually had**: "your streak is at 6" beats
  "we miss you". If the app cannot name the value, it has not earned the notification.
- No day-0 blast. Ask for notification permission at a moment of demonstrated value (the
  onboarding playbooks cover priming), and send the first reminder only after there is something
  real to say.
- Frequency capped, quiet hours respected, cadence user-controllable in settings. Losing
  notification permission to one spammy week is unrecoverable churn.
- Win-back is one honest message ("your streak is repairable until Sunday"), not a drip campaign.

## 6. Ethics — the hard line

Engagement mechanics are the easiest place in the app to slide into manipulation. Refuse:

- **Slot-machine variable rewards** — randomized payouts engineered for compulsion.
- **Manufactured anxiety** — streak mechanics or copy designed to make the user feel bad for
  living their life; guilt-tripping mascots; "your pet died" mechanics.
- **Fake urgency/scarcity** in engagement surfaces (mirrors CONVERSION_PLAYBOOK §6).
- **Dark cadence** — notifications engineered around the cap, or re-asking permission in a loop.

The test: would the mechanic still make sense if the user read exactly how it works? Habit-forming
by being *genuinely rewarding* is the goal; habit-forming by exploiting psychology is a `block`.

## 7. Measure the right things

Instrument every mechanic end to end: `celebration_shown`, `streak_extended` / `streak_repaired`,
`milestone_reached`, `mascot_interacted`, `reminder_sent` / `reminder_opened`. The questions a later
run must be able to answer: does D1/D7 retention differ for users who hit milestone 1 in session
one? Do reminder-opens correlate with value moments? If nothing is measured, nothing here can be
called working.

## 8. Review rubric (the engagement reviewer applies this)

| Dimension | ship | fix-first |
|---|---|---|
| Celebration economy | Peak moments celebrated, sized to achievement, session-one win exists | Celebrates everything, or first session ends with no earned win |
| Streak design | Forgiving, comeback-framed, fits the app's usage shape | Punitive, unrepairable, or bolted onto a non-habit app |
| Milestone ladder | Next milestone visible and reachable, front-loaded | No visible next step, or first milestone days away |
| Mascot | Passes the fit test; states map to real data; consistent art | Fails fit test but shipped anyway; random emoting; clip-art |
| Cadence | Value-tied, capped, controllable | Day-0 blasts, uncapped, or "we miss you" spam |
| Ethics | Passes the §6 test | Any refusal-list mechanic → **block** |
| Instrumentation | Events for trigger → seen → acted | Mechanics shipped blind |
