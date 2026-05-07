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
export PATH="\$JAVA_HOME/bin:\$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:\$ANDROID_SDK_ROOT/platform-tools:$GRADLE_DIR/bin:\$BUN_INSTALL/bin:\$PATH"
# --- end KAppMaker block ---
EOF
fi

# ---------- 11. projects directory + top-level CLAUDE.md ----------
PROJECTS_DIR="$HOME/projects"
CLAUDE_MD_URL="${CLAUDE_MD_URL:-https://raw.githubusercontent.com/KAppMaker/KAppMakerDeveloperBot/main/templates/projects-CLAUDE.md}"

log "Creating projects directory at $PROJECTS_DIR"
mkdir -p "$PROJECTS_DIR"

if [[ ! -f "$PROJECTS_DIR/CLAUDE.md" ]]; then
  log "Downloading workspace CLAUDE.md from $CLAUDE_MD_URL"
  if ! curl -fsSL "$CLAUDE_MD_URL" -o "$PROJECTS_DIR/CLAUDE.md"; then
    warn "Failed to download CLAUDE.md template — you can add one manually later at $PROJECTS_DIR/CLAUDE.md"
    rm -f "$PROJECTS_DIR/CLAUDE.md"
  fi
else
  log "Top-level CLAUDE.md already exists, skipping (delete it to fetch the default again)"
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
     /plugin marketplace add KAppMaker/KAppMaker-CLI
     /plugin install kappmaker@KAppMaker-CLI
     /plugin marketplace add anthropics/claude-code
     /plugin install telegram@anthropic

4. Configure Telegram with your bot token:
     /telegram:configure

5. Pair your Telegram account:
     /telegram:access
   Then send /start to your bot in Telegram and approve the pairing.

6. Run Claude inside tmux so it survives SSH disconnect:
     tmux new -s claude
     cd ~/projects && claude
   Detach: Ctrl+B then D    Reattach: tmux attach -t claude

7. Optional: log into GitHub CLI for app repo pushes:
     gh auth login

────────────────────────────────────────────────────────────
Reminder: iOS builds need macOS/Xcode, so .ipa builds won't work
on this VPS. App Store Connect metadata setup via kappmaker still works.
────────────────────────────────────────────────────────────
NEXT
