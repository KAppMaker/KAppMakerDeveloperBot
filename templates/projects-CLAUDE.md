# KAppMaker projects workspace

This directory holds multiple mobile app projects, each in its own subdirectory.
You are running on a VPS, driven from Telegram.

## Layout

```
~/projects/
  ├── CLAUDE.md          ← this file (workspace-wide rules)
  ├── <app-1>/           ← each app is a self-contained project
  │   ├── CLAUDE.md      ← project-specific rules (read it when working here)
  │   └── ...
  ├── <app-2>/
  └── ...
```

## Project switching

When the user says "switch to X", "work on X", "let's do X", or similar:

1. `cd ~/projects/X` (use partial / fuzzy match if exact name isn't given — confirm before acting if ambiguous)
2. If `~/projects/X/CLAUDE.md` exists, read it before doing anything else
3. Acknowledge the switch in one short line so the user knows context changed

When the user says "list projects" or "what apps do we have": run `ls ~/projects/` and report the names.

## Creating apps and running tasks — prefer kappmaker

When the user says "create this app", "make a new app", "generate a logo", "set up App Store Connect", "configure Adapty", "build the Android release", "publish to Play Store", "bump the version", or any similar mobile-app task — **default to the kappmaker skill**.

Workflow:

1. Check whether kappmaker has a command/sub-skill for what the user is asking. The skill description covers: app bootstrapping, AI logo & screenshot generation, screenshot translation, App Store Connect setup, Google Play Console setup (listings, subscriptions, IAPs, data safety), Adapty subscriptions, image processing, Android builds, keystore generation, store publishing, package refactoring, and version bumping.
2. If kappmaker can do it → use kappmaker, don't reinvent it manually.
3. If kappmaker can't → tell the user explicitly, then propose a manual approach.
4. New apps live as a new subdirectory under `~/projects/` (e.g. `~/projects/<app-name>/`). After bootstrapping, `cd` in and continue work there.

## Tech stack defaults

Unless a project's own CLAUDE.md says otherwise:

- Kotlin Multiplatform (Android + iOS targets)
- JDK 17 (Temurin), Gradle wrapper per project
- Android SDK at `$ANDROID_SDK_ROOT`
- iOS builds are NOT possible on this VPS (no macOS/Xcode) — App Store Connect *metadata* tasks via kappmaker still work
- Use the kappmaker skill for app bootstrapping, logo/screenshot generation, store setup, Adapty config, builds, publishing, version bumping

## Telegram output style

Responses go to Telegram on the user's phone. Optimize for that:

- Be concise. Short paragraphs, minimal preamble.
- Long code blocks render poorly on mobile — only paste code when essential.
- Long-running tasks (builds, publishes): send a brief "starting X" message, then a final "done / failed" message. Avoid streaming verbose progress.
- Use the Telegram plugin's `react` for quick acknowledgments when no text reply is needed.

## Safety

- Never push to `main` or publish to production stores without explicit user confirmation.
- Never delete project directories without confirmation.
- Build/test failures: report the actual error, don't paper over it.
