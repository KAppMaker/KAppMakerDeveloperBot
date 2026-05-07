# KAppMaker Developer Bot

Bootstrap a VPS to run [Claude Code](https://claude.com/claude-code) with the [Telegram plugin](https://github.com/anthropics/claude-code) and the [KAppMaker CLI](https://github.com/KAppMaker/KAppMaker-CLI) skill. Once set up, you can drive your KAppMaker workflows (create apps, generate logos, configure stores, build & publish Android releases) from Telegram on your phone.

## Quick start

On a fresh Ubuntu/Debian VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/KAppMaker/KAppMakerDeveloperBot/main/setup-vps.sh | bash
```

Or, if you'd rather review first:

```bash
wget https://raw.githubusercontent.com/KAppMaker/KAppMakerDeveloperBot/main/setup-vps.sh
less setup-vps.sh
bash setup-vps.sh
```

The script is idempotent — re-running it skips anything already installed.

## What gets installed

| Component | Version | Purpose |
|---|---|---|
| `git`, `curl`, `tmux`, `unzip`, `build-essential` | latest | Base tooling |
| `python3`, `pip`, `venv` | system | Used by some KAppMaker tools |
| Temurin JDK | 17 | Required for Android Gradle Plugin / KMP |
| Android SDK cmdline-tools + `platforms;android-34` + `build-tools;34.0.0` | latest | Build & sign APK/AAB on the VPS |
| Gradle | 9.4.1 | Standalone Gradle (project wrappers override this) |
| Node.js | 22 | Runtime for Claude Code |
| Bun | latest | Required by the Telegram plugin |
| Claude Code | latest | `@anthropic-ai/claude-code` global npm |
| GitHub CLI (`gh`) | latest | Push generated app repos to GitHub |

Environment variables (`JAVA_HOME`, `ANDROID_SDK_ROOT`, `ANDROID_HOME`, `BUN_INSTALL`, `PATH`) are persisted to `~/.bashrc` in a marked block.

A `~/projects/` directory is created with a top-level `CLAUDE.md` that defines workspace-wide rules: how to switch between projects ("switch to fittracker"), tech-stack defaults, and Telegram-friendly output style. Each app you create lives in its own subdirectory and can have its own `CLAUDE.md` for project-specific rules.

## Post-install (interactive — do these on the VPS)

The script prints these steps when it finishes; they can't be automated.

1. **Reload shell**
   ```bash
   source ~/.bashrc
   ```

2. **Log into Claude** with your Pro/Max subscription
   ```bash
   claude
   ```
   Open the printed URL in your laptop browser, paste the auth code back.

3. **Install plugins** (inside Claude)
   ```
   /plugin marketplace add KAppMaker/KAppMaker-CLI
   /plugin install kappmaker@KAppMaker-CLI
   /plugin marketplace add anthropics/claude-code
   /plugin install telegram@anthropic
   ```

4. **Configure Telegram** with your BotFather token
   ```
   /telegram:configure
   ```

5. **Pair your Telegram account**
   ```
   /telegram:access
   ```
   Send `/start` to your bot from Telegram, then approve the pairing in the terminal.

6. **Run inside tmux** so Claude survives SSH disconnect
   ```bash
   tmux new -s claude
   claude
   ```
   Detach: `Ctrl+B` then `D` · Reattach: `tmux attach -t claude`

7. **Optional — log into GitHub CLI** for app repo pushes
   ```bash
   gh auth login
   ```

## Using it from Telegram

Once paired, message your bot. The `kappmaker` skill auto-loads when your prompt matches its triggers. Examples:

- `Create a new app called FitTracker for fitness logging`
- `Generate a logo for FitTracker`
- `Build the Android release`
- `Publish to Play Store internal testing`
- `Bump version to 1.2.0`

## Limitations

- **iOS builds are not possible on a Linux VPS** — `.ipa` builds need macOS/Xcode. App Store Connect *metadata* setup via kappmaker still works fine; only the actual iOS compile step is unavailable.
- **Subscription vs. API:** Running Claude Code on a VPS is meant for *your own interactive use* via Telegram, not as a multi-user service or scripted automation pipeline. If you need always-on, multi-user, or scheduled automation, use an Anthropic API key instead.

## Architecture

```
┌─────────────┐         ┌──────────────────────────┐
│  You (📱)   │ ──────► │  Telegram Bot (BotFather)│
└─────────────┘         └────────────┬─────────────┘
                                     │ long-poll
                                     ▼
                        ┌──────────────────────────┐
                        │  VPS (this repo's script)│
                        │  ┌────────────────────┐  │
                        │  │ Claude Code        │  │
                        │  │  ├─ telegram plugin│  │
                        │  │  └─ kappmaker skill│  │
                        │  └────────────────────┘  │
                        │  + JDK 17, Android SDK,  │
                        │    Gradle, Node, gh      │
                        └──────────────────────────┘
```

## Troubleshooting

- **Adoptium repo fails on your distro** — your Debian/Ubuntu codename may not be in their apt repo yet. Fall back to `sudo apt-get install -y openjdk-17-jdk` and adjust `JAVA_HOME` to `/usr/lib/jvm/java-17-openjdk-${ARCH}`.
- **Android cmdline-tools URL 404s** — Google rotates the version number. Get the current link from <https://developer.android.com/studio#command-line-tools-only> and update `setup-vps.sh`.
- **Telegram bot doesn't respond** — check that bot privacy is set to *Disable* via `@BotFather` → `/setprivacy`, otherwise the bot only sees commands.
- **Claude can't see plugins after install** — restart the `claude` session.
