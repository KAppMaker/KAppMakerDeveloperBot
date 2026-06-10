#!/usr/bin/env bash
# KAppMaker VPS bootstrap
# Installs everything needed to drive Claude Code + Telegram + kappmaker on a fresh Ubuntu/Debian VPS.
#
# Usage:
#   curl -fsSL https://your-host/setup-vps.sh | bash
#   # or after copying the file:
#   bash setup-vps.sh
#
# Idempotent: safe to re-run. Skips steps that are already done.
# Note: iOS builds are NOT possible on a Linux VPS (need macOS/Xcode).
#       This script covers Android builds + everything else kappmaker does.

set -euo pipefail

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[err]\033[0m  %s\n' "$*" >&2; exit 1; }

# ---------- 0. sanity ----------
command -v apt-get >/dev/null || die "This script targets Debian/Ubuntu (apt-get not found)."

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO=""
  SUDO_E=""
  # Running as root installs per-user state (Android SDK, ~/.bashrc env, skills, loop
  # template) into /root — wasted, since the bot can't use --dangerously-skip-permissions
  # as root. The cloud path runs this as a non-root user (and sets KAPP_NONINTERACTIVE),
  # so only warn for an interactive manual root run.
  if [[ "${KAPP_NONINTERACTIVE:-0}" != "1" ]]; then
    warn "Running as root. Recommended: create a non-root sudo user and run this AS that user"
    warn "  (see the README 'Quick start'):  adduser devuser && usermod -aG sudo devuser && su - devuser"
    warn "Continuing as root in 5s — Ctrl-C to abort and switch users."
    sleep 5
  fi
else
  SUDO="sudo"
  SUDO_E="sudo -E"
  command -v sudo >/dev/null || die "Need sudo or run as root."
fi

export DEBIAN_FRONTEND=noninteractive
ARCH="$(dpkg --print-architecture)"   # amd64 / arm64

# ---------- 1. system packages ----------
log "Installing base system packages"
$SUDO apt-get update -y
$SUDO apt-get install -y \
  curl wget git tmux unzip zip \
  build-essential ca-certificates gnupg lsb-release \
  python3 python3-pip python3-venv \
  software-properties-common

# ---------- 2. JDK 17 (Temurin) ----------
log "Installing JDK 17"
if ! java -version 2>&1 | grep -q '"17\.'; then
  $SUDO mkdir -p /etc/apt/keyrings
  wget -qO- https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | $SUDO gpg --dearmor -o /etc/apt/keyrings/adoptium.gpg
  echo "deb [signed-by=/etc/apt/keyrings/adoptium.gpg] https://packages.adoptium.net/artifactory/deb $(lsb_release -cs) main" \
    | $SUDO tee /etc/apt/sources.list.d/adoptium.list >/dev/null
  $SUDO apt-get update -y
  $SUDO apt-get install -y temurin-17-jdk
else
  log "JDK 17 already installed, skipping"
fi
JAVA_HOME="/usr/lib/jvm/temurin-17-jdk-${ARCH}"
export JAVA_HOME PATH="$JAVA_HOME/bin:$PATH"

# ---------- 3. Android SDK ----------
ANDROID_SDK_ROOT="${ANDROID_SDK_ROOT:-$HOME/android-sdk}"
log "Installing Android SDK at $ANDROID_SDK_ROOT"
if [[ ! -d "$ANDROID_SDK_ROOT/cmdline-tools/latest" ]]; then
  mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"
  TMP_ZIP="$(mktemp --suffix=.zip)"
  wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O "$TMP_ZIP"
  unzip -q "$TMP_ZIP" -d "$ANDROID_SDK_ROOT/cmdline-tools"
  mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$ANDROID_SDK_ROOT/cmdline-tools/latest"
  rm -f "$TMP_ZIP"
fi
export ANDROID_SDK_ROOT ANDROID_HOME="$ANDROID_SDK_ROOT"
export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"

log "Accepting Android SDK licenses + installing platforms/build-tools"
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager --install "platform-tools" "platforms;android-34" "build-tools;34.0.0" >/dev/null

# ---------- 4. Gradle ----------
GRADLE_VERSION="9.4.1"
GRADLE_DIR="/opt/gradle-${GRADLE_VERSION}"
log "Installing Gradle ${GRADLE_VERSION}"
if [[ ! -d "$GRADLE_DIR" ]]; then
  TMP_ZIP="$(mktemp --suffix=.zip)"
  wget -q "https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip" -O "$TMP_ZIP"
  $SUDO unzip -q "$TMP_ZIP" -d /opt
  rm -f "$TMP_ZIP"
fi
export PATH="$GRADLE_DIR/bin:$PATH"

# ---------- 5. Node.js 22 ----------
log "Installing Node.js 22"
if ! command -v node >/dev/null || ! node --version | grep -q '^v22'; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | $SUDO_E bash -
  $SUDO apt-get install -y nodejs
fi

# ---------- 6. Bun (required by Telegram plugin) ----------
log "Installing Bun"
if ! command -v bun >/dev/null && [[ ! -x "$HOME/.bun/bin/bun" ]]; then
  curl -fsSL https://bun.sh/install | bash
fi
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

# ---------- 7. Claude Code ----------
log "Installing Claude Code (global npm)"
$SUDO npm install -g @anthropic-ai/claude-code

# ---------- 8. KAppMaker CLI ----------
log "Installing KAppMaker CLI (global npm)"
$SUDO npm install -g kappmaker

# ---------- 9. GitHub CLI ----------
log "Installing GitHub CLI"
if ! command -v gh >/dev/null; then
  $SUDO mkdir -p /etc/apt/keyrings
  wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | $SUDO tee /etc/apt/keyrings/githubcli-archive-keyring.gpg >/dev/null
  $SUDO chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  $SUDO apt-get update -y
  $SUDO apt-get install -y gh
fi

# ---------- 9b. cloudflared (for web preview tunnels) ----------
log "Installing cloudflared"
if ! command -v cloudflared >/dev/null; then
  TMP_DEB="$(mktemp --suffix=.deb)"
  wget -q "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}.deb" -O "$TMP_DEB"
  $SUDO dpkg -i "$TMP_DEB"
  rm -f "$TMP_DEB"
fi

# ---------- 9c. preview helper scripts ----------
PREVIEW_BASE_URL="${PREVIEW_BASE_URL:-https://raw.githubusercontent.com/KAppMaker/KAppMakerDeveloperBot/main/templates/bin}"
log "Installing preview scripts to ~/bin"
mkdir -p "$HOME/bin"
for script in preview preview-stop kapp-service-install; do
  if curl -fsSL "$PREVIEW_BASE_URL/$script" -o "$HOME/bin/$script"; then
    chmod +x "$HOME/bin/$script"
  else
    warn "Failed to download $script — fetch manually later from $PREVIEW_BASE_URL/$script"
  fi
done

# ---------- 9c2. session-history hook (context recovery after a restart) ----------
# The always-on Telegram bot restarts as a FRESH Claude after a crash/reboot, with
# no memory of the prior conversation. This Stop hook saves the last few exchanges
# to ~/.claude/session-history.md every turn so a restarted Claude can recover what
# it was working on (it reads the file on demand — see the workspace CLAUDE.md).
log "Installing session-history hook to ~/bin"
if curl -fsSL "$PREVIEW_BASE_URL/claude-history.py" -o "$HOME/bin/claude-history.py"; then
  chmod +x "$HOME/bin/claude-history.py"
  # Register a user-level Stop hook idempotently (never clobbers existing settings).
  mkdir -p "$HOME/.claude"
  if python3 - "$HOME/.claude/settings.json" "python3 $HOME/bin/claude-history.py" <<'PY'
import json, sys
path, cmd = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}
stop = data.setdefault("hooks", {}).setdefault("Stop", [])
present = any(h.get("command") == cmd for grp in stop for h in (grp.get("hooks") or []))
if not present:
    stop.append({"matcher": "", "hooks": [{"type": "command", "command": cmd}]})
    with open(path, "w") as f:
        json.dump(data, f, indent=2)
    print("registered")
else:
    print("already present")
PY
  then
    log "Session-history Stop hook registered in ~/.claude/settings.json"
  else
    warn "Could not register session-history hook — add a Stop hook for 'python3 ~/bin/claude-history.py' to ~/.claude/settings.json manually."
  fi
else
  warn "Failed to download claude-history.py — fetch manually later from $PREVIEW_BASE_URL/claude-history.py"
fi

# ---------- 9c3. recommended global skills (caveman + ui-ux-pro-max) ----------
# Two high-value skills installed globally (~/.claude/skills) so they're available in
# every session with no interactive /plugin step:
#   caveman      — terse output (fewer tokens; tidy Telegram replies on a phone)
#   ui-ux-pro-max — UI/UX design intelligence (Jetpack Compose / SwiftUI)
# Best-effort — never fail the run. Set KAPP_SKIP_SKILLS=1 to skip. Optional extras
# (kotlin-lsp, prototype, handoff, git-guardrails) are documented in the README.
if [[ "${KAPP_SKIP_SKILLS:-0}" != "1" ]]; then
  mkdir -p "$HOME/.claude"

  log "Installing 'caveman' skill (terse output)"
  # caveman's installer is `npx github:JuliusBrussee/caveman` (auto-detects Claude Code).
  if ( cd "$HOME" && npx -y github:JuliusBrussee/caveman </dev/null ) >/dev/null 2>&1; then
    log "caveman installed"
  else
    warn "caveman install skipped/failed — add later: npx -y github:JuliusBrussee/caveman"
  fi

  log "Installing 'ui-ux-pro-max' skill (UI/UX design intelligence)"
  if $SUDO npm install -g uipro-cli >/dev/null 2>&1; then
    # `uipro init` installs into <cwd>/.claude/skills — run from $HOME for a global install.
    if ( cd "$HOME" && uipro init --ai claude --force </dev/null ) >/dev/null 2>&1; then
      log "ui-ux-pro-max installed (~/.claude/skills)"
    else
      warn "ui-ux-pro-max init skipped/failed — add later: (cd ~ && uipro init --ai claude --force)"
    fi
  else
    warn "uipro-cli install failed — add later: npm i -g uipro-cli && (cd ~ && uipro init --ai claude --force)"
  fi
else
  log "KAPP_SKIP_SKILLS=1 — skipping recommended skills (caveman, ui-ux-pro-max)"
fi

# ---------- 9d. self-improve loop template + installer ----------
# The loop is an OPT-IN scaffold: deployed here, installed per-app with `kapp-loop-install`,
# and OFF until a human triggers it. We fetch the repo tarball and extract the two pieces.
LOOP_REPO="${LOOP_REPO:-KAppMaker/KAppMakerDeveloperBot}"
LOOP_REF="${LOOP_REF:-main}"
LOOP_TEMPLATE_DIR="$HOME/projects/.loop-template"
log "Installing self-improve loop template to $LOOP_TEMPLATE_DIR"
mkdir -p "$HOME/projects" "$HOME/bin"
TMP_TGZ="$(mktemp --suffix=.tgz)"
TMP_EXTRACT="$(mktemp -d)"
if curl -fsSL "https://github.com/${LOOP_REPO}/archive/refs/heads/${LOOP_REF}.tar.gz" -o "$TMP_TGZ" \
   && tar -xzf "$TMP_TGZ" -C "$TMP_EXTRACT"; then
  SRC_ROOT="$(find "$TMP_EXTRACT" -maxdepth 1 -type d -name '*KAppMakerDeveloperBot*' | head -1)"
  if [[ -n "$SRC_ROOT" && -d "$SRC_ROOT/templates/loop" ]]; then
    rm -rf "$LOOP_TEMPLATE_DIR"
    cp -R "$SRC_ROOT/templates/loop" "$LOOP_TEMPLATE_DIR"
    chmod +x "$LOOP_TEMPLATE_DIR"/scripts/*.sh 2>/dev/null || true
    cp "$SRC_ROOT/templates/bin/kapp-loop-install" "$HOME/bin/kapp-loop-install"
    chmod +x "$HOME/bin/kapp-loop-install"
    log "Loop template + 'kapp-loop-install' installed (loop stays OFF until triggered)"
  else
    warn "Loop template not found in tarball — skipping. Fetch manually from $LOOP_REPO later."
  fi
else
  warn "Failed to download loop template tarball — skipping. Re-run later or fetch manually."
fi
rm -rf "$TMP_TGZ" "$TMP_EXTRACT"

# ---------- 9e. swap + build memory tuning ----------
# Android/Gradle builds are memory-hungry. With no swap, a build that exceeds RAM
# triggers the Linux OOM killer, which can take down Claude or your tmux session
# ("my session randomly died"). Add a swapfile as a backstop and right-size the
# JVM heaps for this box, leaving headroom for the OS and the always-on Claude bot.
log "Configuring swap + Gradle memory (prevents OOM kills during builds)"
RAM_MB="$(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)"

# 1) swapfile — only if no swap is active and there's room on disk.
SWAP_TOTAL_MB="$(free -m 2>/dev/null | awk '/Swap:/{print $2}' || echo 0)"
if [[ "${SWAP_TOTAL_MB:-0}" -eq 0 ]]; then
  DISK_FREE_MB="$(df --output=avail -m / 2>/dev/null | tail -1 | tr -d ' ' || echo 0)"
  if [[ "${DISK_FREE_MB:-0}" -ge 8192 ]]; then
    log "No swap found — creating a 4G swapfile"
    if $SUDO fallocate -l 4G /swapfile 2>/dev/null || $SUDO dd if=/dev/zero of=/swapfile bs=1M count=4096 status=none; then
      $SUDO chmod 600 /swapfile
      $SUDO mkswap /swapfile >/dev/null
      $SUDO swapon /swapfile
      grep -q '^/swapfile ' /etc/fstab 2>/dev/null || echo '/swapfile none swap sw 0 0' | $SUDO tee -a /etc/fstab >/dev/null
      # Prefer RAM; lean on swap only under real pressure.
      echo 'vm.swappiness=10' | $SUDO tee /etc/sysctl.d/99-kappmaker-swap.conf >/dev/null
      $SUDO sysctl -q vm.swappiness=10 2>/dev/null || true
    else
      warn "Could not create swapfile — skipping (builds may OOM on low-RAM boxes)."
    fi
  else
    warn "Low free disk (<8G) — skipping swapfile creation."
  fi
else
  log "Swap already present (${SWAP_TOTAL_MB}M) — leaving it as-is"
fi

# 2) VPS-local Gradle tuning. Written to GRADLE_USER_HOME (~/.gradle), which
# overrides a project's gradle.properties — so dev-machine settings stay intact.
# KAppMaker apps ship -Xmx4G for BOTH the Gradle and Kotlin daemons (~8G of heap),
# which is tuned for a workstation, not a shared VPS also running the Claude bot.
GRADLE_PROPS="$HOME/.gradle/gradle.properties"
if [[ "${RAM_MB:-0}" -gt 0 && ! -f "$GRADLE_PROPS" ]]; then
  GRADLE_XMX=$(( RAM_MB * 40 / 100 )); [[ "$GRADLE_XMX" -lt 1024 ]] && GRADLE_XMX=1024; [[ "$GRADLE_XMX" -gt 4096 ]] && GRADLE_XMX=4096
  KOTLIN_XMX=$(( RAM_MB * 25 / 100 )); [[ "$KOTLIN_XMX" -lt 768 ]] && KOTLIN_XMX=768; [[ "$KOTLIN_XMX" -gt 3072 ]] && KOTLIN_XMX=3072
  mkdir -p "$HOME/.gradle"
  cat > "$GRADLE_PROPS" <<EOF
# Managed by setup-vps.sh — VPS-local Gradle tuning (overrides project gradle.properties).
# Sized for ${RAM_MB}MB RAM, leaving headroom for the OS and the Claude bot.
# Delete this file to fall back to the project's own settings.
org.gradle.jvmargs=-Xmx${GRADLE_XMX}m -XX:MaxMetaspaceSize=512m -Dfile.encoding=UTF-8
kotlin.daemon.jvmargs=-Xmx${KOTLIN_XMX}m
org.gradle.parallel=false
org.gradle.workers.max=2
EOF
  log "Wrote $GRADLE_PROPS (Gradle ${GRADLE_XMX}m / Kotlin ${KOTLIN_XMX}m, sized for ${RAM_MB}M RAM)"
elif [[ -f "$GRADLE_PROPS" ]]; then
  log "~/.gradle/gradle.properties already exists — leaving it as-is"
fi

# ---------- 10. persist env vars ----------
log "Persisting env vars to ~/.bashrc"
BLOCK_MARK="# --- KAppMaker VPS env (managed by setup-vps.sh) ---"
if ! grep -qF "$BLOCK_MARK" "$HOME/.bashrc" 2>/dev/null; then
  cat >> "$HOME/.bashrc" <<EOF

$BLOCK_MARK
export JAVA_HOME="$JAVA_HOME"
export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"
export ANDROID_HOME="\$ANDROID_SDK_ROOT"
export BUN_INSTALL="\$HOME/.bun"
export PATH="\$HOME/bin:\$JAVA_HOME/bin:\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:\$ANDROID_SDK_ROOT/platform-tools:$GRADLE_DIR/bin:\$BUN_INSTALL/bin:\$PATH"
# --- end KAppMaker block ---
EOF
fi

# Also expose the toolchain env to the always-on systemd service, which does NOT
# read ~/.bashrc. claude-telegram.service loads this via EnvironmentFile so that
# Gradle/Android builds triggered by the bot find JAVA_HOME / ANDROID_SDK_ROOT / PATH.
ENV_FILE="$HOME/.config/kappmaker/env"
mkdir -p "$HOME/.config/kappmaker"
cat > "$ENV_FILE" <<EOF
JAVA_HOME=$JAVA_HOME
ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT
ANDROID_HOME=$ANDROID_SDK_ROOT
BUN_INSTALL=$HOME/.bun
PATH=$HOME/bin:$JAVA_HOME/bin:$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$GRADLE_DIR/bin:$HOME/.bun/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
EOF

# ---------- 11. projects directory + top-level CLAUDE.md / MEMORY.md ----------
PROJECTS_DIR="$HOME/projects"
CLAUDE_MD_URL="${CLAUDE_MD_URL:-https://raw.githubusercontent.com/KAppMaker/KAppMakerDeveloperBot/main/templates/projects-CLAUDE.md}"
MEMORY_MD_URL="${MEMORY_MD_URL:-https://raw.githubusercontent.com/KAppMaker/KAppMakerDeveloperBot/main/templates/projects-MEMORY.md}"

log "Creating projects directory at $PROJECTS_DIR"
mkdir -p "$PROJECTS_DIR"

if [[ ! -f "$PROJECTS_DIR/CLAUDE.md" ]]; then
  log "Downloading workspace CLAUDE.md from $CLAUDE_MD_URL"
  if ! curl -fsSL "$CLAUDE_MD_URL" -o "$PROJECTS_DIR/CLAUDE.md"; then
    warn "Failed to download CLAUDE.md template — you can add one manually later at $PROJECTS_DIR/CLAUDE.md"
    rm -f "$PROJECTS_DIR/CLAUDE.md"
  fi
else
  # File exists — check whether the template has changed since it was installed (template
  # updates carry bot-behavior fixes, e.g. how questions are delivered over Telegram).
  TMP_CLAUDE="$(mktemp)"
  if curl -fsSL "$CLAUDE_MD_URL" -o "$TMP_CLAUDE"; then
    if cmp -s "$TMP_CLAUDE" "$PROJECTS_DIR/CLAUDE.md"; then
      log "Top-level CLAUDE.md is up to date with the template."
    elif [[ "${KAPP_NONINTERACTIVE:-0}" == "1" || ! -e /dev/tty ]]; then
      cp "$TMP_CLAUDE" "$PROJECTS_DIR/CLAUDE.md.new"
      warn "Workspace CLAUDE.md template has changed. Kept your file; wrote the new version to"
      warn "  $PROJECTS_DIR/CLAUDE.md.new — review and replace/merge manually."
    else
      warn "Your workspace CLAUDE.md differs from the latest template (updates carry bot-behavior fixes)."
      read -r -p "Overwrite with the new template? Your current file is backed up to CLAUDE.md.bak [y/N] " ans </dev/tty
      if [[ "$ans" =~ ^[Yy]$ ]]; then
        cp "$PROJECTS_DIR/CLAUDE.md" "$PROJECTS_DIR/CLAUDE.md.bak"
        cp "$TMP_CLAUDE" "$PROJECTS_DIR/CLAUDE.md"
        log "CLAUDE.md updated (previous version saved as CLAUDE.md.bak)."
      else
        cp "$TMP_CLAUDE" "$PROJECTS_DIR/CLAUDE.md.new"
        log "Kept your CLAUDE.md. New template saved as CLAUDE.md.new for manual merge."
      fi
    fi
  else
    warn "Failed to download CLAUDE.md template to check for updates — kept the existing file."
  fi
  rm -f "$TMP_CLAUDE"
fi

if [[ ! -f "$PROJECTS_DIR/MEMORY.md" ]]; then
  log "Downloading workspace MEMORY.md from $MEMORY_MD_URL"
  if ! curl -fsSL "$MEMORY_MD_URL" -o "$PROJECTS_DIR/MEMORY.md"; then
    warn "Failed to download MEMORY.md template — you can add one manually later at $PROJECTS_DIR/MEMORY.md"
    rm -f "$PROJECTS_DIR/MEMORY.md"
  fi
else
  log "Top-level MEMORY.md already exists, skipping (preserves your saved memory)"
fi

# ---------- 12. kappmaker config init (interactive) ----------
log "Running 'kappmaker config init' (will prompt for API keys / credentials)"
if [[ -e /dev/tty ]]; then
  # Read from /dev/tty so prompts work even when script is run via curl|bash
  kappmaker config init </dev/tty || warn "kappmaker config init exited non-zero — re-run manually if needed"
else
  warn "No /dev/tty available — skipping. Run 'kappmaker config init' manually after this script finishes."
fi

# ---------- done ----------
log "System install complete!"
cat <<'NEXT'

────────────────────────────────────────────────────────────
NEXT STEPS (interactive — cannot be scripted)
────────────────────────────────────────────────────────────

0. SECURE THE VPS FIRST. Don't leave SSH open to the world, and don't run
   the bot as root. Put SSH behind Tailscale, default-deny with UFW, and run
   Claude as a non-root sudo user (required for --dangerously-skip-permissions).
   See the "Securing the VPS" section of the README for the checklist + a
   community hardening skill that does it interactively.

1. Reload your shell so env vars take effect:
     source ~/.bashrc

   (If you skipped 'kappmaker config init' above, run it now.
    Docs: https://cli.kappmaker.com/)

2. Log into Claude with your subscription:
     cd ~/projects
     claude
   (Open the printed URL in your laptop browser, paste the auth code back.)
   Always start Claude from ~/projects so the workspace CLAUDE.md is loaded.

3. Inside Claude, install the plugins:
   KAppMaker skill (guide: https://cli.kappmaker.com/guides/claude-code-skill):
     /plugin marketplace add KAppMaker/KAppMaker-CLI
     /plugin install kappmaker@KAppMaker-CLI
   Telegram channel plugin:
     /plugin install telegram@claude-plugins-official
     /reload-plugins

4. Configure Telegram — pass your BotFather token inline:
     /telegram:configure 123456789:AAHfiqksKZ8...
   (writes TELEGRAM_BOT_TOKEN=... to ~/.claude/channels/telegram/.env)

5. Pair your Telegram account:
   DM your bot in Telegram — it replies with a 6-character code. Then:
     /telegram:access pair <code>
   Lock it down so only you can reach the bot:
     /telegram:access policy allowlist

6. Run Claude inside tmux WITH the Telegram channel active
   (so messages from your bot are received):
     tmux new -s claude
     cd ~/projects && claude --channels plugin:telegram@claude-plugins-official
   Detach: Ctrl+B then D    Reattach: tmux attach -t claude

   Note: plain `claude` starts a normal interactive session and does NOT
   listen on Telegram. The --channels flag is required.

7. Optional: log into GitHub CLI for app repo pushes:
     gh auth login

8. Optional: enable the self-improving dev loop on an app (OFF by default):
     cd ~/projects/<app> && kapp-loop-install
   Then just message (terminal or Telegram) to start, e.g.
     "improve the onboarding conversion and keep going until it's done"
   and "stop the loop" to end. No slash commands.

────────────────────────────────────────────────────────────
Reminder: iOS builds need macOS/Xcode, so .ipa builds won't work
on this VPS. App Store Connect metadata setup via kappmaker still works.
────────────────────────────────────────────────────────────
NEXT
