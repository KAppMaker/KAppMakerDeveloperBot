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
| KAppMaker CLI | latest | `kappmaker` global npm — used by the kappmaker plugin |
| GitHub CLI (`gh`) | latest | Push generated app repos to GitHub |
| `cloudflared` | latest | Cloudflare quick tunnels for web (Wasm/JS) preview URLs |
| `preview` / `preview-stop` | bundled | Helper scripts in `~/bin` that wrap `cloudflared` for one-command preview links |

Environment variables (`JAVA_HOME`, `ANDROID_SDK_ROOT`, `ANDROID_HOME`, `BUN_INSTALL`, `PATH`) are persisted to `~/.bashrc` in a marked block.

A `~/projects/` directory is created with two workspace files:

- `CLAUDE.md` — workspace-wide rules: project switching ("switch to fittracker"), project lifecycle, kappmaker-first workflow, build previews, asset attachment, safety confirmations, and Telegram output style.
- `MEMORY.md` — user-controlled persistent memory. Empty by default; you populate it via Telegram with messages like *"remember: all new repos should be private"* / *"forget X"* / *"what do you remember"*. Claude reads it before every meaningful task and respects it (memory entries override CLAUDE.md defaults when they conflict).

Each app you create lives in its own subdirectory and can have its own `CLAUDE.md` for project-specific rules.

## Post-install (interactive — do these on the VPS)

The script prints these steps when it finishes; they can't be automated.

> Note: the bootstrap script runs `kappmaker config init` interactively at the end. If for any reason it was skipped (e.g. no TTY), run it manually before doing anything else: `kappmaker config init`. Docs: <https://cli.kappmaker.com/>.

1. **Reload shell**
   ```bash
   source ~/.bashrc
   ```

2. **Log into Claude** with your Pro/Max subscription
   ```bash
   cd ~/projects
   claude
   ```
   Open the printed URL in your laptop browser, paste the auth code back. Always start Claude from `~/projects` so the workspace CLAUDE.md is loaded.

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

6. **Run inside tmux with the Telegram channel active** so Claude listens for your bot messages and survives SSH disconnect
   ```bash
   tmux new -s claude
   cd ~/projects && claude --channels plugin:telegram@claude-plugins-official
   ```
   Detach: `Ctrl+B` then `D` · Reattach: `tmux attach -t claude`

   > **Important:** plain `claude` (without `--channels`) starts a normal interactive session and does **not** listen on Telegram. The `--channels` flag is what opens the listener.

7. **Log into GitHub CLI** for app repo pushes
   ```bash
   gh auth login
   ```
   Use the dedicated bot account from the *GitHub authentication* section below — **don't use your personal account on the VPS**.

## GitHub authentication (recommended)

A VPS can be compromised. If your *personal* GitHub credentials live on it, an attacker gets your private repos, can force-push to `main`, etc. Use a dedicated **machine user account** instead — fully isolated, easy to revoke.

### One-time setup

1. **Create a separate GitHub account** for the bot (free). Use a `+` alias on your email so it lands in your inbox: `you+kappmakerbot@gmail.com` → register at <https://github.com/signup>. Enable 2FA on it (separate authenticator entry from your personal one).

2. **Add it to your `KAppMaker` org** with the *Member* role (browser):
   - Org → People → Invite member
   - Repos it needs to push to → Manage access → grant write

3. **Generate an SSH key on the VPS** for this account:
   ```bash
   ssh-keygen -t ed25519 -C "kappmaker-bot-vps" -f ~/.ssh/kappmaker_bot
   cat ~/.ssh/kappmaker_bot.pub
   ```
   Copy the printed public key.

4. **Add the public key to the bot account** (browser, logged in as the bot): <https://github.com/settings/keys> → New SSH key.
   *Optional hardening:* if your VPS has a static IP, prefix the key with `from="1.2.3.4" ` so it only works from that IP.

5. **Tell SSH to use this key for github.com** (on the VPS):
   ```bash
   cat >> ~/.ssh/config <<'EOF'
   Host github.com
     HostName github.com
     User git
     IdentityFile ~/.ssh/kappmaker_bot
     IdentitiesOnly yes
   EOF
   chmod 600 ~/.ssh/config
   ```

6. **Set the git identity** so commits are attributed to the bot, not `root@vps`:
   ```bash
   git config --global user.name "KAppMaker Bot"
   git config --global user.email "you+kappmakerbot@gmail.com"
   ```

7. **Verify**:
   ```bash
   ssh -T git@github.com
   # → "Hi kappmaker-bot! You've successfully authenticated..."
   ```

8. **Now log into `gh`** (step 7 above) — choose **SSH** and point at the same key file. `gh` will use it for HTTPS API calls and for git push.

### What this protects against

| Scenario | With personal creds | With bot account |
|---|---|---|
| VPS gets root-level compromise | Attacker gets all your private repos, can force-push, delete branches | Attacker only gets repos in the KAppMaker org that bot has write to |
| Bot key leaks | Have to rotate personal key (affects all your machines) | Revoke one key on one account, done |
| You stop using the VPS | Need to remember to revoke the key | Just delete the bot account or remove from org |

## Web previews (Wasm / JS builds)

When kappmaker builds the web target, the output is just static files — but you're on your phone, so the script bundles a `preview` helper that gives you a public URL via Cloudflare Tunnel.

```bash
# After: ./gradlew :webApp:jsBrowserDistribution
preview ~/projects/<app>/MobileApp/webApp/build/dist/js/productionExecutable
# → prints e.g. https://random-words-here.trycloudflare.com
```

Open the URL on your phone and you're previewing your KMP web build. When you're done:

```bash
preview-stop          # stop the default-port preview
preview-stop --all    # stop everything
```

Claude knows this workflow — just ask via Telegram: *"build webapp for fittracker and send me the preview link"* and it'll run the build, start the tunnel, and reply with the URL.

**Tunnel notes:**
- URL changes every time the tunnel restarts (it's a free Cloudflare quick tunnel — no account needed)
- Tunnel only lives while `cloudflared` is running on the VPS
- For a permanent URL, set up a *named* Cloudflare Tunnel against your own domain — out of scope here, but the same `cloudflared` binary supports it

## Using it from Telegram

Once paired, message your bot. The `kappmaker` skill auto-loads when your prompt matches its triggers. Examples:

- `Create a new app called FitTracker for fitness logging`
- `Generate a logo for FitTracker`
- `Build the Android release`
- `Publish to Play Store internal testing`
- `Bump version to 1.2.0`

**Memory commands** — teach Claude your preferences once, they stick across sessions:

- `Remember: all new GitHub repos should be private`
- `Remember: use MIT license by default`
- `What do you remember?` — Claude shows the contents of `~/projects/MEMORY.md`
- `Forget the MIT license preference`

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
