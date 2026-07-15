#!/usr/bin/env bash
# Always-on Claude + Telegram runner (managed by systemd: claude-telegram.service).
#
# This is the heart of the "always-on" product value: it keeps a Claude Code
# session listening on the customer's Telegram bot, survives crashes and reboots
# (systemd Restart=always + WantedBy=multi-user.target), and replaces the manual
# `tmux` flow from the README.
#
# It waits (without crash-looping noisily) until the customer has finished the
# on-box setup — i.e. logged into Claude AND saved their Telegram bot token.
# ZERO-KNOWLEDGE: those secrets are created on the box by the customer; this
# script only checks for their presence, never reads or transmits them.

set -uo pipefail

CLAUDE_CREDS="$HOME/.claude/.credentials.json"
CLAUDE_CONFIG_DIR="$HOME/.claude"
TELEGRAM_ENV="$HOME/.claude/channels/telegram/.env"
TELEGRAM_ACCESS="$HOME/.claude/channels/telegram/access.json"
TELEGRAM_CHANNEL="plugin:telegram@claude-plugins-official"
PROJECTS_DIR="$HOME/projects"
KAPP_ENV="$HOME/.config/kappmaker/env"
SETUP_SENT_MARKER="$HOME/.config/kappmaker/.setup-complete-sent"

# Control-plane callback URL persisted by bootstrap.sh (signed, secret-free).
# shellcheck disable=SC1090
[[ -f "$KAPP_ENV" ]] && source "$KAPP_ENV"

have_claude_login() {
  # Authoritative check via `claude auth status` (prints {"loggedIn": true|false}).
  # Do NOT `grep -r oauth ~/.claude` — the Telegram channel plugin's node_modules
  # (pkce-challenge, jose, MCP SDK auth) contain that string, so the grep gives a
  # false positive and would start the bot before the customer has signed in.
  claude auth status 2>/dev/null | grep -q '"loggedIn" *: *true'
}

have_telegram_token() {
  [[ -f "$TELEGRAM_ENV" ]] && grep -qs "TELEGRAM_BOT_TOKEN=..*" "$TELEGRAM_ENV"
}

# Setup is only truly complete once the customer's Telegram account is PAIRED —
# i.e. their numeric user ID is in access.json's allowFrom. Until then the bot
# is online (so pairing codes can be minted) but no one can reach the assistant,
# and we must NOT tear down the browser-setup terminal or tell the control plane
# "setup_complete". A public bot with an empty allowlist is not a finished setup.
have_paired() {
  [[ -f "$TELEGRAM_ACCESS" ]] || return 1
  python3 - "$TELEGRAM_ACCESS" <<'PY' 2>/dev/null
import json, sys
try:
    sys.exit(0 if json.load(open(sys.argv[1])).get("allowFrom") else 1)
except Exception:
    sys.exit(1)
PY
}

# Pull the customer's current PUBLIC ssh key from the control plane (signed
# URL, no secret) and install it — so a key added in the dashboard opens the
# box within one restart cycle, without a rebuild. Strictly validated: only a
# plain "type base64" line is ever written.
sync_customer_key() {
  [[ -n "${SERVER_KEY_URL:-}" ]] || return 0

  local key
  key="$(curl -fsS --max-time 10 "$SERVER_KEY_URL" 2>/dev/null | head -n 1)" || return 0

  [[ "$key" =~ ^(ssh-(rsa|ed25519)|ecdsa-sha2-[a-z0-9-]+)\ [A-Za-z0-9+/=]+$ ]] || return 0

  install -d -m 700 "$HOME/.ssh"
  if ! grep -qsF "$key" "$HOME/.ssh/authorized_keys" 2>/dev/null; then
    printf '%s\n' "$key" >> "$HOME/.ssh/authorized_keys"
    chmod 600 "$HOME/.ssh/authorized_keys"
    echo "[claude-telegram] Installed the customer's ssh key from the dashboard."
  fi
}

sync_customer_key

if ! have_claude_login || ! have_telegram_token; then
  echo "[claude-telegram] Setup not finished yet (Claude login and/or Telegram token missing)."
  echo "[claude-telegram] Waiting — will start automatically once setup is complete."
  # Exit non-zero so systemd restarts us after RestartSec, polling for setup.
  exit 1
fi

cd "$PROJECTS_DIR" || exit 1

# Credentials are in place → bring the bot ONLINE below no matter what, so the
# customer can DM it and receive a pairing code. But the setup FLOW is only
# finished once they've paired (their ID is in allowFrom). The teardown +
# "setup_complete" callback are therefore gated on have_paired:
#   - Normally the wizard does both the moment pairing succeeds.
#   - This block is the fallback for the SSH setup path and for reboots — it
#     runs on a later restart, once access.json shows an allowlisted sender.
# Both are one-shot (markers), so wizard + runner never double-fire.
if have_paired; then
  # Tear down the one-time browser-setup terminal (ttyd + Caddy) and close its
  # firewall ports. The teardown writes /etc/kappmaker/.setup-done, so this
  # guard skips forever after. Passwordless sudo; -n = never prompt.
  if [[ -x /usr/local/bin/kappmaker-setup-teardown && ! -f /etc/kappmaker/.setup-done ]]; then
    sudo -n /usr/local/bin/kappmaker-setup-teardown \
      || echo "[claude-telegram] Browser-setup teardown failed — will retry on next start."
  fi

  # Tell the control plane setup is done (flips the dashboard to Active). Carries
  # only the lifecycle state + the PUBLIC bot username (for the "Open your bot"
  # button). The bot token itself never leaves this box.
  if [[ -n "${SERVER_CALLBACK_URL:-}" && ! -f "$SETUP_SENT_MARKER" ]]; then
    BOT_USERNAME=""
    # Pure-bash read: the token never appears in any subprocess argv (ps-safe).
    TG_TOKEN=""
    while IFS= read -r line; do
      case "$line" in
        TELEGRAM_BOT_TOKEN=*)
          TG_TOKEN="${line#TELEGRAM_BOT_TOKEN=}"
          TG_TOKEN="${TG_TOKEN%\"}"; TG_TOKEN="${TG_TOKEN#\"}"
          break;;
      esac
    done < "$TELEGRAM_ENV"
    if [[ -n "$TG_TOKEN" ]]; then
      BOT_USERNAME="$(curl -fsS "https://api.telegram.org/bot${TG_TOKEN}/getMe" 2>/dev/null \
        | sed -n 's/.*"username":"\([A-Za-z0-9_]*\)".*/\1/p')"
    fi
    unset TG_TOKEN

    if curl -fsS -X POST "$SERVER_CALLBACK_URL" \
        --data-urlencode "state=setup_complete" \
        --data-urlencode "message=customer setup complete" \
        ${BOT_USERNAME:+--data-urlencode "bot_username=$BOT_USERNAME"} \
        >/dev/null 2>&1; then
      touch "$SETUP_SENT_MARKER"
    else
      echo "[claude-telegram] setup_complete callback failed — will retry on next start."
    fi
  fi
fi

# Start the always-on channel session INSIDE TMUX. claude NEEDS A TTY to run
# interactively (under systemd there is none — it would fall back to --print
# mode and die with "Input must be provided either through stdin or as a prompt
# argument"); tmux provides the PTY *and* makes the live session attachable, so
# the owner can SSH in and watch/drive Claude working:
#
#     tmux attach -t claude      (detach again: Ctrl+B then D)
#
# Supervision model: systemd runs THIS script; the script starts the tmux
# session and then blocks while it exists. When claude exits/crashes the tmux
# session dies, the wait-loop returns, we exit non-zero, and systemd's
# Restart=always relaunches us — re-running the gates above (key sync, paired
# finalization) before starting a fresh session. Stopping the service kills the
# whole cgroup, tmux server included.
#
# --dangerously-skip-permissions enables hands-off operation (safe: the box is
# locked to the owner; the one-time bypass warning is pre-accepted at provision
# via ~/.claude/settings.json "skipDangerousModePermissionPrompt", alongside the
# theme + folder-trust flags — otherwise those prompts would block a headless
# start). Until the customer is paired the bot only hands out pairing codes.
TMUX_SESSION="claude"
tmux kill-session -t "$TMUX_SESSION" 2>/dev/null || true
tmux new-session -d -s "$TMUX_SESSION" \
  claude --channels "$TELEGRAM_CHANNEL" --dangerously-skip-permissions
echo "[claude-telegram] Claude is live in tmux session '$TMUX_SESSION' — watch it: tmux attach -t $TMUX_SESSION"
while tmux has-session -t "$TMUX_SESSION" 2>/dev/null; do
  sleep 5
done
echo "[claude-telegram] Session ended — systemd will restart it."
exit 1
