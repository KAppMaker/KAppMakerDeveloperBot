# KAppMaker projects workspace

This directory holds multiple mobile app projects, each in its own subdirectory.
You are running on a VPS, driven from Telegram.

## Layout

```
~/projects/
  ├── CLAUDE.md          ← this file (workspace-wide rules)
  ├── MEMORY.md          ← user-controlled persistent memory (read & respect)
  ├── <app-1>/           ← each app is a self-contained project
  │   ├── CLAUDE.md      ← project-specific rules (read it when working here)
  │   └── ...
  ├── <app-2>/
  └── ...
```

## Persistent memory (MEMORY.md)

`~/projects/MEMORY.md` holds user-controlled preferences and decisions that persist across sessions. **Read it at the start of any non-trivial task** (project switch, new app, publish, repo creation, store setup, etc.) and honor whatever's there.

Memory commands the user may give via Telegram:

- *"remember X"* / *"save to memory: X"* / *"from now on, X"* → append a one-line entry to the appropriate section in MEMORY.md (Preferences / Decisions / Project-specific notes). Confirm with one short reply.
- *"forget X"* / *"drop X from memory"* → remove the matching line. Confirm.
- *"what do you remember"* / *"show memory"* → read MEMORY.md and reply with its contents (or just the relevant section if the user asks specifically).

**Precedence**: when memory conflicts with the defaults below in this CLAUDE.md, **memory wins**. Example: tech-stack default is KMP, but if memory says "use Compose Multiplatform Web only", follow that.

If two memory entries conflict, ask the user which to keep — don't silently pick one.

## Project switching

When the user says "switch to X", "work on X", "let's do X", or similar:

1. `cd ~/projects/X` (use partial / fuzzy match if exact name isn't given — confirm before acting if ambiguous)
2. If `~/projects/X/CLAUDE.md` exists, read it before doing anything else
3. Acknowledge the switch in one short line so the user knows context changed

When the user says "list projects" or "what apps do we have": run `ls ~/projects/` and report the names (skip dotfiles like `.archived/`).

## Project lifecycle

- **Starting new project** — when the user says "let's start a new app", "new project", "starting new project now", or similar:
  1. `cd ~/projects` so you're not in any existing project's context.
  2. Read `~/projects/MEMORY.md` for relevant preferences (repo privacy, license, default stack, etc.).
  3. Confirm with the user: app name + a one-line scope. Don't auto-pick a name.
  4. Then run `kappmaker create <AppName>` and continue from inside the new directory.

- **Archiving a project** — when the user says "archive X", "I'm done with X", "remove X from active projects":
  1. Confirm with the user using the project name spelled back.
  2. Move it: `mv ~/projects/X ~/projects/.archived/X` (create `.archived/` if missing).
  3. Don't delete — `.archived/` keeps it recoverable.

- **Resuming a project** — "let's get back to X", "resume X" → same flow as project switching, plus a one-line recap of `~/projects/X/CLAUDE.md` (if it exists) so the user remembers where they left off.

## Creating apps and running tasks — prefer kappmaker

When the user says "create this app", "make a new app", "generate a logo", "set up App Store Connect", "configure Adapty", "build the Android release", "publish to Play Store", "bump the version", or any similar mobile-app task — **default to the kappmaker tooling** (the `kappmaker` CLI + the `kappmaker:kappmaker` skill).

Workflow:

1. Check whether kappmaker can do what the user is asking. If unsure, run `kappmaker --help` or `kappmaker <command> --help`. Full docs: <https://cli.kappmaker.com/>.
2. If kappmaker can do it → use kappmaker, don't reinvent it manually.
3. If kappmaker can't → tell the user explicitly, then propose a manual approach.
4. New apps live as a new subdirectory under `~/projects/` (e.g. `~/projects/<app-name>/`). After bootstrapping, `cd` in and continue work there.

### Common kappmaker CLI commands

| Command | Purpose |
|---|---|
| `kappmaker config init` | Set API keys & preferences (run once before anything else) |
| `kappmaker create <AppName>` | Full 13-step app scaffolding workflow |
| `kappmaker create-logo` | Generate AI app logo |
| `kappmaker create-appstore-app` | Create App Store Connect listing |
| `kappmaker gpc setup` | Configure Google Play Console |
| `kappmaker adapty setup` | Set up Adapty subscriptions / paywalls |
| `kappmaker publish` | Build + upload to stores |
| `kappmaker refactor` | Rename package / app ID |
| `kappmaker generate-screenshots` / `translate-screenshots` | Screenshot tooling |

If a credential is missing, kappmaker will say so — re-run `kappmaker config init` to add it.

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
- Use the Telegram plugin's `react` for quick acknowledgments when no text reply is needed.

## Long-running tasks and cancellation

Tasks that take more than ~10 seconds (Gradle builds, kappmaker publishes, Wasm compilations, store uploads) need different handling than chat-style replies:

- **Start**: react with ⏳ on the user's message, or send a short "starting X for `<project>`" reply if more context is needed. Don't paste the full command.
- **During**: do NOT stream stdout/progress to Telegram. The user is on their phone — chatty progress is noise.
- **End**: send exactly one final reply: *"done — <one-line outcome>"* on success, *"failed — <one-line reason>"* on failure with the actual error (truncated if huge — paste the most relevant 5-10 lines).
- **Cancellation** — if the user says "cancel", "stop", "abort", or similar mid-task: kill the in-progress process (e.g. `pkill -f gradle` for a Gradle build, the kappmaker process, etc.). Confirm with one short "stopped X" reply.
- **Concurrent requests** — if a build is already running for a project and the user requests another, ask: queue, replace (cancel current first), or ignore?

## Web (Wasm/JS) build previews

After building a web target (typically `./gradlew :webApp:jsBrowserDistribution`), the static output lives at `<project>/MobileApp/webApp/build/dist/js/productionExecutable`. The user can't open it locally — they're on their phone — so expose it as a public URL with the `preview` helper:

```bash
preview <build-output-dir>
# prints e.g. https://random-words.trycloudflare.com  on stdout
```

How it works: spins up a local `python3 -m http.server` on port 8080, opens a Cloudflare quick tunnel pointing at it, returns the public HTTPS URL. No account, no domain, no firewall changes.

After a successful Wasm/JS build:

1. Run `preview <build-output-dir>` and capture stdout
2. Telegram-reply the URL: `"Build done — preview: https://...trycloudflare.com (live until you stop it)"`
3. When the user is done, run `preview-stop` (single port) or `preview-stop --all` (everything)

Notes:

- Each call to `preview` kills the previous server on the same port, so iterating is fine — same project = URL refreshes with the new build
- Different ports for different projects in parallel: `preview <dir> 8081`, `preview <dir2> 8082`
- The URL changes every time the tunnel restarts. Don't promise stability.
- For large/heavy assets, the first load may take a few seconds while Cloudflare warms up.

## Sending generated assets back via Telegram

When a tool generates an asset the user would want to see — logos, screenshots, build artifacts (APK/AAB), exported PDFs — **attach the file to your Telegram reply** via the `files` parameter. Don't just print the file path in text; the user is on their phone and can't browse the VPS filesystem.

```
reply({ chat_id: "...", text: "Here's the logo:", files: ["/root/projects/<app>/Assets/logo.png"] })
```

Rules:

- Use **absolute paths** (`/root/projects/...`, not `~/projects/...` — `~` doesn't expand inside the tool call).
- Logos / screenshots → attach the image.
- Build outputs (APK / AAB) → attach if under 50 MB (Telegram Bot API limit). Above that, tell the user the path and suggest external hosting (S3 / R2 / etc.).
- Photo uploads via `sendPhoto` are capped at 10 MB and Telegram will compress them — for full-quality screenshots over 10 MB, send as document.
- Don't attach intermediate / working files unless the user asks.
- The VPS does NOT need to be publicly reachable for this — uploads go directly from VPS → Telegram servers via outbound HTTPS.

## Safety

### Confirmations required (always ask first)

For these actions, require an explicit "yes" with the **target name spelled back to the user** before proceeding:

- Production publish — Play Store production track, App Store live release
- Push to `main` (or `master`) on any repo
- Force-push (`git push --force`, `--force-with-lease`)
- Deletion — files, directories, branches, GitHub repos, store listings
- `rm -rf`, `git reset --hard`, `git clean -fd`, dropping a database
- Spending operations — anything that costs real money (paid AI generations beyond defaults, store fees, infra changes)

Format the confirmation request like: *"About to publish `fittracker` to App Store **production**. Confirm with 'yes publish fittracker'?"*. Don't accept ambiguous "yeah ok" for high-stakes ops — if unsure, ask again.

### Secret hygiene

- Never echo API keys, tokens, keystore passwords, OAuth secrets, or credentials to chat. If the user pastes one, acknowledge receipt without quoting it back.
- Never commit any of: `.env`, `.env.*`, `*.keystore`, `*.jks`, `service-account*.json`, App Store API `.p8` files, `secrets/*`, `credentials/*`. Add them to `.gitignore` if missing.
- If a secret was accidentally committed, tell the user immediately and recommend rotating it.

### Branch hygiene

- Use feature branches for non-trivial changes. Direct commits to `main` only for tiny fixes or initial scaffolding of a new project.
- Never force-push to `main`.
- Default to opening a PR for review when working on shared/public repos.

### Build / test failures

Report the actual error. Don't silently retry or paper over.

If a retry is plausibly useful (transient network, flaky test, rate limit), say so explicitly and ask before retrying.

### Cost-aware operations

Operations that hit paid APIs or trigger billable work (large kappmaker logo/screenshot batches, store publishing fees, mass translation runs) should announce themselves before running so the user can stop them in time.
