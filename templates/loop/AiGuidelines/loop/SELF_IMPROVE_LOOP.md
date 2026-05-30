# Self-improving dev loop — the law of this repo

This is the full workflow for the autonomous, self-reviewing improvement loop. `CLAUDE.loop.md`
is the lean rules block and imports this file. When the loop is active, **this document governs
how you work**: how you plan, implement, review, verify, and decide when to stop.

It implements the **Ralph technique** — a Stop hook that re-feeds the turn until the work is done
(see `scripts/loop-guard.sh`). The KAppMaker layer on top is the verification gate, the `PLAN.md`
checklist as completion signal, the specialist reviews, and the ethics rules below. See the project
README's "Self-improving dev loop" section for the relationship to Anthropic's `ralph-wiggum` plugin.

The loop is built for apps generated from the **KAppMaker** boilerplate:
Kotlin Multiplatform + Compose Multiplatform (Android / iOS / Web / Desktop). The Gradle root is
`MobileApp/` inside the app repo. Shared code lives under
`MobileApp/shared/src/commonMain/kotlin/com/measify/kappmaker/`.

**North-star metric:** subscription free→paid conversion AND credit-pack purchase conversion.
Every improvement should ladder up to activation and conversion — ethically (see Ethics below).

---

## The loop never runs by default

Nothing autonomous happens until a human asks for it. The mechanism:

- A **Stop hook** (`scripts/loop-guard.sh`, registered in `.claude/settings.json`) drives iteration.
- The hook is **inert** unless the flag file `.claude/.loop-active` exists. No flag → it exits 0 →
  a normal session stops normally.
- You **create** that flag only when a human gives a start trigger, and **remove** it on a stop
  trigger, on the iteration cap, or when the plan is complete.

See "Triggers" below for the exact start/stop intents. There are **no slash commands** in the
trigger path — it is all plain language, so it works identically from a terminal or from Telegram.

---

## The loop, step by step

### 1. Plan
The **orchestrator** turns the human's goal into `PLAN.md`: small, independently verifiable
`- [ ]` items grouped under milestones, each tagged with the reviewer(s) who should critique it,
e.g. `- [ ] Surface value before signup [onboarding, paywall]`.

Rules for a good plan:
- Each item is **one** change that can be verified on its own. If you can't describe how to verify
  it, split it.
- Order by impact on the north-star metric, then by dependency.
- Keep the plan honest: if scope grows mid-run, append new `- [ ]` items at the bottom — never
  silently widen an in-flight item.

`start-loop.sh` seeds `PLAN.md` from `PLAN.template.md` if no plan exists yet; the orchestrator
then tailors the milestones/items to the actual goal the human gave.

### 2. Implement (one item per iteration)
- Work the **top unchecked `- [ ]` item only**. Never batch multiple items in one iteration.
- Make the **smallest change** that satisfies the item.
- A **git checkpoint is taken before editing** (`start-loop.sh` on the first item; thereafter the
  workflow commits after each verified item, so the working tree is clean at the start of each
  iteration). If the tree is dirty when you begin an item, commit or stash the prior work first.

### 3. Review (parallel specialists)
Spawn the relevant specialist sub-agents to critique the change (cap **3–4 concurrent**). Pick by
the item's reviewer tags and by what files changed:
- `onboarding-specialist` — onboarding / activation / first-run.
- `paywall-conversion-specialist` — paywall, subscription, credit-pack, pricing.
- `ui-ux-reviewer` — any Compose UI / design-system / screen change.
- `qa-engineer` — correctness, edge cases, tests, build safety.

Each specialist is **read-mostly**: it reviews and recommends but does not edit code. It ends its
turn by writing `.loop/reviews/<agent>-<ISO8601>.md` with these sections:
- **Verdict** — `ship` / `fix-first` / `block`
- **Findings** — severity-tagged (`blocker` / `major` / `minor` / `nit`)
- **Concrete changes** — `file:line` + the suggested edit
- **Out of scope** — things noticed but deliberately not addressed now

### 4. Synthesize
The orchestrator reads the reviews and **decides which suggestions to apply** — by cost vs. impact,
**not** "apply everything". A `fix-first` on a real blocker must be addressed before the box can be
checked; `minor`/`nit` items can be deferred to new plan items. Log every accept/reject with a
one-line reason in `.loop/decisions.md`. Then apply the accepted changes (orchestrator/implementer
only — specialists never write code).

### 5. Verify (the gate)
Run the tiered Gradle gate (below) from the Gradle root. **Only passing verification may check a
box.** Reviews are advisory; the build and tests are law. A red build is never checked off and is
never forced green.

### 6. Mark & continue
On a green gate: flip the item to `- [x]`, append any newly-discovered follow-ups to the bottom of
`PLAN.md`, commit the verified change, and end your turn. The Stop hook then decides whether to loop
again (more `- [ ]` remain and under the cap) or stop.

### 7. Finish
When **no `- [ ]` items remain**:
1. Write `.loop/reports/run-<ISO8601>.md` containing: items completed, key decisions (link
   `.loop/decisions.md`), verification results per item, and open follow-ups.
2. If a Telegram chat context is available (the loop was driven from a Telegram message), send a
   **concise** summary via the Telegram `reply` tool — one short paragraph, not the whole report.
   Always write the markdown report regardless; the Telegram message is best-effort.
3. Remove the flag (`scripts/stop-loop.sh`) so the loop goes inert again.

---

## Tiered verification gate

Run from the Gradle root — `./gradlew` if present at repo root, else `MobileApp/gradlew`.
`loop-guard.sh` auto-detects the root and picks the tier from `git diff --name-only` since the
checkpoint.

**Always (fast tier):**
```
./gradlew spotlessApply
./gradlew spotlessCheck
./gradlew :shared:jvmTest
```

**If UI changed** — any changed path under `presentation/` or `designsystem/`, any file matching
`*Screen*.kt`, or any file containing `@Preview` — also run:
```
./gradlew :shared:testAndroidHostTest
./gradlew :shared:verifyRoborazziAndroidHostTest
```

When Roborazzi verification fails because of an **intentional** UI change (the snapshot legitimately
moved), do NOT auto-record to force green. Review the visual diff, confirm the change is wanted, and
only then run `:shared:recordRoborazziAndroidHostTest` **deliberately**, noting it in
`.loop/decisions.md`. If the change was not intended, treat the failure as a real regression.

**Slow / manual (NOT in the auto-gate):** `:androidApp:assembleDebug`, iOS framework link. Too slow
to run every iteration; mention them as optional deep checks before a release, not part of the loop.

---

## Triggers (plain language, no slash commands)

**Start intent** — e.g. "improve the onboarding conversion and keep going until it's done", "start
the self-improve loop on the paywall", "run the dev loop". On recognizing start intent:
1. Run `scripts/start-loop.sh "<goal text>"` — it takes a git checkpoint, seeds/refreshes `PLAN.md`,
   and creates the `.claude/.loop-active` flag.
2. Have the orchestrator tailor `PLAN.md` to the goal.
3. Begin item 1.

**Stop intent** — e.g. "stop", "pause the loop", "that's enough for now". On recognizing stop intent:
1. Run `scripts/stop-loop.sh` — removes the flag.
2. Confirm in one short line. In-flight work already committed stays; nothing is reverted.

The iteration cap and a red build also end the loop automatically (the guard handles both).

---

## Hard rules (non-negotiable)

- **One item per iteration.** No batching.
- **Never check a box on a red build.** Verification is law; reviews are advice.
- **Never auto-record Roborazzi snapshots to force green.** Confirm the UI change is intentional first.
- **Never edit the no-touch list** (see `CLAUDE.loop.md` / `.claude/settings.json`) without asking
  the human first — secrets, signing keys, generated build output, CI workflows.
- **Specialists don't write code.** Only the orchestrator/implementer edits.
- **Ethics of conversion work (refuse dark patterns).** Optimize free→paid and credit-pack
  conversion with honest means only: clear value, fair trial framing, transparent pricing, easy
  cancellation. **Refuse** fake scarcity/countdowns, deceptive or buried cancel flows, pre-checked
  upsells, misleading "free" labels, or confusing price anchoring — even if it would lift the
  metric. If a requested change crosses this line, stop and flag it instead of implementing it.
