<!-- KAPPMAKER-SELF-IMPROVE-LOOP:START -->
## Self-improving dev loop (opt-in, off by default)

This app has an autonomous, self-reviewing improvement loop installed. **It does not run unless a
human triggers it**, and it only iterates while the flag file `.claude/.loop-active` exists.

The full workflow — plan → implement → parallel specialist review → synthesize → verify → mark →
finish — is the law of this repo:

@AiGuidelines/loop/SELF_IMPROVE_LOOP.md

### Triggering (plain language — works from terminal or Telegram, no slash commands)

- **Start**: when the human says something like "improve <goal> and keep going until it's done",
  "start the self-improve loop", or "run the dev loop" → run `scripts/start-loop.sh "<goal>"`
  (checkpoint + seed `PLAN.md` + set the flag), then begin the top `PLAN.md` item.
- **Stop**: when the human says "stop", "pause the loop", "that's enough" → run
  `scripts/stop-loop.sh` (removes the flag) and confirm in one line.

### The few rules you must hold in mind every iteration

- Work **one** `- [ ]` item per iteration; smallest change; commit after each verified item.
- **Verification is law.** Run the tiered Gradle gate from the Gradle root (`MobileApp/gradlew`).
  Never check a box on a red build. Never auto-record Roborazzi snapshots to force green.
- Spawn relevant specialists (cap 3–4) to review; they recommend, only you/orchestrator edit.
- **No-touch (ask first):** secrets, signing keys, `**/build/**`, `.github/workflows/**` —
  see `.claude/settings.json` deny list.
- **Conversion work stays ethical.** No dark patterns / fake scarcity / deceptive cancel — refuse
  even if it would lift the metric.
<!-- KAPPMAKER-SELF-IMPROVE-LOOP:END -->
