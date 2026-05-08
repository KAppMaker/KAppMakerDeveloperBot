# Memory

User-controlled persistent memory for the KAppMaker workspace. Claude reads this file before any non-trivial action and respects whatever's in it. The contract:

- **Read** at the start of any meaningful task (project switch, app creation, publish, repo setup, etc.).
- **Append** when the user says *"remember X"*, *"save to memory: X"*, *"from now on, X"*, or similar.
- **Remove** when the user says *"forget X"*, *"drop X from memory"*, or similar.
- **Show** when the user says *"what do you remember"*, *"show memory"*, or similar — reply with the relevant sections.
- **Precedence**: if a memory entry conflicts with workspace defaults in `CLAUDE.md`, the memory entry wins. If two memory entries conflict, ask the user which one to keep.

Keep entries short — one line per item. Use the section that fits; if nothing fits, add to *Decisions*.

## Preferences

<!-- Durable user preferences. Examples (not active, just illustrative):
     - GitHub repos: private by default
     - License: MIT for new apps
     - Default screenshot device: iPhone 15 Pro
     - Languages for screenshot translation: en, tr, es
-->

## Decisions

<!-- One-off choices the user wants remembered across sessions. Examples:
     - Use Adapty (not RevenueCat) for all new apps
     - Skip Firebase Crashlytics; we use Sentry
-->

## Project-specific notes

<!-- Per-project notes keyed by project name. Examples:
     ### fittracker
     - Adapty paywall variant: "premium-trial"

     ### recipeapp
     - Skip iOS for now, web + Android only
-->
