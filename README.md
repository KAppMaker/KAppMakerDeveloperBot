# KAppMaker Developer Bot

Bootstrap a VPS to run [Claude Code](https://claude.com/claude-code) with the [Telegram plugin](https://github.com/anthropics/claude-code) and the [KAppMaker CLI](https://github.com/KAppMaker/KAppMaker-CLI) skill. Once set up, you can drive your KAppMaker workflows (create apps, generate logos, configure stores, build & publish Android releases) from Telegram on your phone.

## Contents

1. [Quick start](#quick-start) — one-command bootstrap of a fresh VPS
2. [Securing the VPS](#securing-the-vps-do-this-first) — **do this first**: Tailscale, UFW, SSH lockdown
3. [What gets installed](#what-gets-installed) — the toolchain the script sets up
4. [Post-install](#post-install-interactive--do-these-on-the-vps) — non-root user, login to Claude, plugins, Telegram
5. [GitHub authentication](#github-authentication-recommended) — dedicated bot account & SSH key
6. [Web previews](#web-previews-wasm--js-builds) — public URLs for Wasm/JS builds
7. [Using it from Telegram](#using-it-from-telegram) — example commands & memory
8. [Self-improving dev loop](#self-improving-dev-loop) — opt-in autonomous improvement loop
9. [Working with Claude Code effectively](#working-with-claude-code-effectively) — high-value habits & best practices
10. [Limitations](#limitations) · [Architecture](#architecture) · [Troubleshooting](#troubleshooting)

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

## Securing the VPS (do this first)

A VPS is a computer wired directly to the entire internet — ~8 billion people can knock on its door and try to get in. Treat it that way. **You want it reachable only by you** (and, if you host a public site, only by Cloudflare in front of it). This matters even more here because you may run Claude with `--dangerously-skip-permissions` for hands-off Telegram/loop use — so the box itself must be locked down to just you.

The model (battle-tested by folks running real apps on their own infra — see [@levelsio's VPS-lockdown tweet](https://x.com/levelsio/status/2033546675063554213)):

- **SSH only over [Tailscale](https://tailscale.com)** — put the server on a private mesh network and make that the *only* way in. No public SSH surface to brute-force.
- **Default-deny firewall (UFW)** — block all inbound, then open only what you truly need.
- **Cloudflare in front of any public web** — if (and only if) you serve a website, allow inbound `443` *from Cloudflare IPs only*, never from the open internet. (The bundled `preview` helper uses **outbound** Cloudflare quick tunnels, so it needs **no** inbound web rule.)

### Non-negotiables checklist

| ✅ | Hardening | Why |
|---|---|---|
| ☐ | SSH **key-only** auth (`PasswordAuthentication no`) | Kills password brute-force |
| ☐ | **Root login off** (`PermitRootLogin no`) + a non-root sudo user (see Post-install) | No direct root attack surface |
| ☐ | **UFW** on, default-deny inbound | Closed by default, open by exception |
| ☐ | **SSH locked to Tailscale** | Public `:22` is never exposed |
| ☐ | **Docker ports bound to `127.0.0.1`** | Docker bypasses UFW via iptables — bind explicitly |
| ☐ | **Unattended security upgrades** | Auto-patch known CVEs |
| ☐ | **fail2ban** | Bans repeat offenders |
| ☐ | **Tested backups** | A backup you've never restored is a wish, not a backup |

### Hardening quick start

1. **Install Tailscale and join your tailnet** (do this *before* touching the firewall, so you don't lock yourself out):
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```
   Confirm you can SSH in over the Tailscale IP (`100.x.y.z`) from your laptop.

2. **Lock the firewall to Tailscale-only SSH:**
   ```bash
   sudo ufw default deny incoming
   sudo ufw default allow outgoing
   sudo ufw allow in on tailscale0 to any port 22 proto tcp   # SSH only over Tailscale
   sudo ufw enable
   ```
   > ⚠️ Keep your provider's web console / rescue session open until you've confirmed Tailscale SSH works — otherwise a bad rule can lock you out. Only after that, remove any public `allow 22` rule.

3. **(Only if hosting a public website) allow `443` from Cloudflare IPs only:**
   ```bash
   for ip in $(curl -s https://www.cloudflare.com/ips-v4); do sudo ufw allow from "$ip" to any port 443 proto tcp; done
   for ip in $(curl -s https://www.cloudflare.com/ips-v6); do sudo ufw allow from "$ip" to any port 443 proto tcp; done
   ```
   Point your domain through Cloudflare (orange-cloud / proxied) so Cloudflare stands in front and absorbs attacks. **Never** open `443`/`80` to `0.0.0.0/0`.

### Let Claude harden it for you

There's a community Claude Code skill that does all of the above interactively — SSH lockdown, UFW, Tailscale, fail2ban, unattended-upgrades, Docker port binding, and backup guidance — in a few minutes:

> **Hardening skill:** <https://gist.github.com/burakeregar/5b8a7bca382ae43342db30f3c04788fc>
>
> Save it to `~/.claude/commands/vps-setup.md` on the VPS, then ask Claude (e.g. *"run the full VPS setup"* / *"harden ssh"*) and it walks you through the rest. Review what it changes before applying — you're handing it root.

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
| `kapp-loop-install` + loop template | bundled | Per-app self-improving dev loop scaffold (opt-in, **off by default**) — see [Self-improving dev loop](#self-improving-dev-loop) |

Environment variables (`JAVA_HOME`, `ANDROID_SDK_ROOT`, `ANDROID_HOME`, `BUN_INSTALL`, `PATH`) are persisted to `~/.bashrc` in a marked block.

A `~/projects/` directory is created with two workspace files:

- `CLAUDE.md` — workspace-wide rules: project switching ("switch to fittracker"), project lifecycle, kappmaker-first workflow, build previews, asset attachment, safety confirmations, and Telegram output style.
- `MEMORY.md` — user-controlled persistent memory. Empty by default; you populate it via Telegram with messages like *"remember: all new repos should be private"* / *"forget X"* / *"what do you remember"*. Claude reads it before every meaningful task and respects it (memory entries override CLAUDE.md defaults when they conflict).

Each app you create lives in its own subdirectory and can have its own `CLAUDE.md` for project-specific rules.

## Post-install (interactive — do these on the VPS)

The script prints these steps when it finishes; they can't be automated.

> Note: the bootstrap script runs `kappmaker config init` interactively at the end. If for any reason it was skipped (e.g. no TTY), run it manually before doing anything else: `kappmaker config init`. Docs: <https://cli.kappmaker.com/>.

### Run as a non-root user (recommended)

Don't run the bot as `root`: it's a security risk, and Claude Code **refuses `--dangerously-skip-permissions` when running as root** — and you'll want that flag for hands-off Telegram / loop operation (see step 6). Create a normal user with sudo and do everything below as that user:

```bash
sudo adduser devuser && sudo usermod -aG sudo devuser
su - devuser
```

Each user has its own env: if you ran the bootstrap as `root`, just **re-run it as `devuser`** (it's idempotent and will set up this user's `~/.bashrc` env block, SDK paths, and tools), or copy the `# --- KAppMaker VPS env ---` block from root's `~/.bashrc` into `devuser`'s and `source ~/.bashrc`.

#### Log in with an SSH key (do this before disabling passwords)

The login password prompt is brute-forceable — switch this user to SSH **key** auth. From **your laptop**, push your public key:

```bash
ssh-copy-id devuser@<server-ip>
# no ssh-copy-id? →
# cat ~/.ssh/id_ed25519.pub | ssh devuser@<server-ip> 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys'
```

Verify you can `ssh devuser@<server-ip>` **without** a password. Only then, turn off password + root login globally:

```bash
sudo sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/'             /etc/ssh/sshd_config
sudo sshd -t && sudo systemctl restart ssh    # sshd -t must pass first
```

> ⚠️ Keep your current SSH session **and** your provider's web console open until a fresh key-based login works — a bad `sshd_config` can lock you out.

#### Passwordless sudo (optional — stops the sudo prompt)

For unattended operation you may not want `sudo` to prompt for a password. Add a validated drop-in (never edit `/etc/sudoers` directly):

```bash
echo "devuser ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/devuser
sudo chmod 440 /etc/sudoers.d/devuser
sudo visudo -c        # must print "parsed OK"
```

> ⚠️ **Tradeoff:** passwordless sudo + `--dangerously-skip-permissions` means the agent effectively *is* root. That's only acceptable because the box is locked to **you** (SSH key-only + [Tailscale](#securing-the-vps-do-this-first) + root login off). If you'd rather keep a safety line, skip this — day-to-day kappmaker/gradle/claude work needs no `sudo` at all; only the one-time setup does.

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

   **KAppMaker skill** — natural-language access to the `kappmaker` CLI ([guide](https://cli.kappmaker.com/guides/claude-code-skill)):
   ```
   /plugin marketplace add KAppMaker/KAppMaker-CLI
   /plugin install kappmaker@KAppMaker-CLI
   ```
   > Alternatively, outside Claude: `npx skills add KAppMaker/KAppMaker-CLI --skill kappmaker`

   **Telegram channel plugin** ([official README](https://github.com/anthropics/claude-plugins-official/blob/main/external_plugins/telegram/README.md)):
   ```
   /plugin install telegram@claude-plugins-official
   /reload-plugins
   ```

4. **Configure Telegram** — pass your BotFather token inline
   ```
   /telegram:configure 123456789:AAHfiqksKZ8...
   ```
   This writes `TELEGRAM_BOT_TOKEN=...` to `~/.claude/channels/telegram/.env`.

5. **Pair your Telegram account.** DM your bot on Telegram — it replies with a **6-character pairing code**. Back in the Claude session:
   ```
   /telegram:access pair <code>
   ```
   Then lock it down so only you can reach the bot:
   ```
   /telegram:access policy allowlist
   ```

6. **Run inside tmux with the Telegram channel active** so Claude listens for your bot messages and survives SSH disconnect
   ```bash
   tmux new -s claude
   cd ~/projects && claude --channels plugin:telegram@claude-plugins-official
   ```
   Detach: `Ctrl+B` then `D` · Reattach: `tmux attach -t claude`

   > **Important:** plain `claude` (without `--channels`) starts a normal interactive session and does **not** listen on Telegram. The `--channels` flag is what opens the listener.

   **Hands-off mode (no permission prompts).** For unattended Telegram use — and for the [self-improving dev loop](#self-improving-dev-loop) to run without stopping to ask — add `--dangerously-skip-permissions` so Claude runs tools without prompting:
   ```bash
   cd ~/projects && claude --channels plugin:telegram@claude-plugins-official --dangerously-skip-permissions
   ```
   > This flag **only works as a non-root user** (see the note above). It removes the per-action approval prompts, so only use it on a VPS you control. The loop scaffold's `no-touch` deny-list (secrets, keystores, `**/build/**`, CI workflows) is still a guardrail, but treat skip-permissions as full trust in the agent.

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

## Self-improving dev loop

An **opt-in** autonomous loop that improves an app one small, verified change at a time. It plans the
work, implements the top item, spins up specialist sub-agents to critique the change, applies the
worthwhile suggestions, runs a real Gradle gate, and only then checks the item off — repeating until
the plan is done or you say stop. Its default goal is **conversion** (free→paid subscriptions +
credit-pack purchases), reviewed ethically (it refuses dark patterns).

It is **not** installed in apps automatically and **never runs until you trigger it** with a plain
message — the same whether you're in the terminal or on Telegram. There are no slash commands.

> **This is our take on the [Ralph technique](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum)** — the same engine Anthropic's `ralph-wiggum` plugin uses: a **Stop hook** that re-feeds the turn until the work is done. On top of that primitive we add a real Gradle verification gate (it never checks a box on a red build), a `PLAN.md` checklist as the completion signal (instead of ralph's exact-string `--completion-promise`), parallel specialist reviews, ethics guardrails, and **plain-language triggers that work over Telegram** (instead of `/ralph-loop`, which doesn't). So the "no slash commands" above is a deliberate divergence from ralph, not a gap.

### 1. Install it into an app (once)

```bash
cd ~/projects/<app>
kapp-loop-install
```

This drops the scaffold into the app: workflow guide in `AiGuidelines/loop/`, specialist sub-agents
in `.claude/agents/`, helper scripts in `scripts/`, a gated Stop hook in `.claude/settings.json`,
and a run-output dir `.loop/`. It also appends a short rules block to the app's `CLAUDE.md`. Your
existing config is never clobbered (if `.claude/settings.json` already exists it writes
`settings.loop.json` for you to merge).

> On the VPS the template is pre-deployed to `~/projects/.loop-template/` by `setup-vps.sh`, so
> `kapp-loop-install` just works. Nothing changes about a normal session until you start the loop.

### 2. Start it — plain language

Just describe the goal and tell it to keep going. Examples (terminal or Telegram):

- *"improve the onboarding conversion and keep going until it's done"*
- *"start the self-improve loop on the paywall"*
- *"run the dev loop — focus on the credit-pack purchase flow"*
- *"work on first-run activation autonomously until the plan is complete"*

On start it takes a git checkpoint, seeds `PLAN.md` from the goal, raises the loop flag, and begins
the first item.

### 3. Stop it — plain language

- *"stop"* · *"pause the loop"* · *"that's enough for now"*

The loop also stops automatically when the plan is complete, when a build/test fails (it never
checks a box on a red build), or when it hits the iteration cap (25 by default).

### What you get back

- `PLAN.md` — the living checklist (✅ done / ☐ remaining), grouped by milestone.
- `.loop/decisions.md` — why each specialist suggestion was accepted or rejected.
- `.loop/reviews/` — each specialist's structured critique per iteration.
- `.loop/reports/run-<timestamp>.md` — a final report when the run finishes. If you started the loop
  from Telegram, it also sends you a concise summary message.

### The specialists

Each reviews against the app's own `AiGuidelines/` and recommends only — code is written by the
orchestrator alone:

| Sub-agent | Focus |
|---|---|
| `orchestrator` | Owns `PLAN.md`, delegates, decides what to apply, enforces the gate |
| `onboarding-specialist` | First-run activation, time-to-value, signup/permission friction |
| `paywall-conversion-specialist` | Subscription + credit-pack conversion, trial framing, pricing (ethical) |
| `ui-ux-reviewer` | Compose UI: tap targets, accessibility, dark mode, snapshot impact |
| `qa-engineer` | Kotlin/coroutine correctness, edge cases, missing tests, build safety |

### Example session (from Telegram)

```
You:  switch to fittracker
Bot:  Switched to fittracker.

You:  install the self-improve loop here
Bot:  Done — loop installed, off by default.

You:  improve the onboarding conversion and keep going until it's done
Bot:  ⏳ Loop started. Seeded PLAN.md (3 milestones, 11 items). Working item 1…
      …(iterates: implement → review → verify → check off)…
Bot:  done — completed 11/11 items. Report: .loop/reports/run-2026-05-29T1430.md
      Highlights: chose OnBoarding variation 2, moved paywall after first value moment,
      fixed 2 a11y issues. All gates green.

You:  stop
Bot:  Loop stopped. Committed work is preserved.
```

The full workflow rules live in each app at `AiGuidelines/loop/SELF_IMPROVE_LOOP.md`.

## Working with Claude Code effectively

A few high-value habits that make the bot (and the loop) produce better work. These are distilled from [shanraisshan/claude-code-best-practice](https://github.com/shanraisshan/claude-code-best-practice) — see it for the full list.

- **Plan before you build.** For anything non-trivial, ask it to plan first (research → plan → execute → review) instead of jumping straight to edits.
- **Keep `CLAUDE.md` lean** (aim under ~200 lines). Push detail into the `AiGuidelines/` files — the loop and specialists already read those.
- **Lean on specialist sub-agents.** Delegating review/research to focused agents keeps the main context clean and the answers sharper (the loop does this automatically).
- **Verification is law, not vibes.** Trust the build/test gate over "looks done" — the loop never checks a box on a red build, and you should hold normal sessions to the same bar.
- **Mind context hygiene.** Start a fresh session for an unrelated task rather than letting one thread sprawl.

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
- **My tmux/Claude session "randomly" dies during a build** — it's almost always the Linux **OOM killer**, not a tmux limit. Android/Gradle builds are memory-hungry (the app ships `-Xmx4G` for *both* the Gradle and Kotlin daemons), and with no swap the kernel kills the biggest process — sometimes Claude or the tmux server. `setup-vps.sh` now adds a swapfile and writes a VPS-sized `~/.gradle/gradle.properties` to prevent this; **re-run `setup-vps.sh` on an existing box** (it's idempotent) to apply. Confirm a past kill with `sudo dmesg -T | grep -i "killed process"`. Also avoid running a build in tmux *and* the always-on bot at once — that doubles the memory pressure.
