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
TELEGRAM_CHANNEL="plugin:telegram@claude-plugins-official"
PROJECTS_DIR="$HOME/projects"
KAPP_ENV="$HOME/.config/kappmaker/env"
SETUP_SENT_MARKER="$HOME/.config/kappmaker/.setup-complete-sent"

# Control-plane callback URL persisted by bootstrap.sh (signed, secret-free).
# shellcheck disable=SC1090
[[ -f "$KAPP_ENV" ]] && source "$KAPP_ENV"

have_claude_login() {
  # Claude stores subscription auth under ~/.claude after `claude` login.
  [[ -f "$CLAUDE_CREDS" ]] || grep -rqs "oauth" "$CLAUDE_CONFIG_DIR" 2>/dev/null
}

have_telegram_token() {
  [[ -f "$TELEGRAM_ENV" ]] && grep -qs "TELEGRAM_BOT_TOKEN=..*" "$TELEGRAM_ENV"
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

# First start with the customer's creds in place: tell the control plane setup
# is done (flips the dashboard to Active). One-shot via marker; carries only the
# lifecycle state + the PUBLIC bot username (for the "Open your bot" button).
# The bot token itself never leaves this box.
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

# --dangerously-skip-permissions enables hands-off Telegram operation. Safe only
# because the box is locked down to the owner (see hardening in bootstrap.sh).
exec claude \
  --channels "$TELEGRAM_CHANNEL" \
  --dangerously-skip-permissions
