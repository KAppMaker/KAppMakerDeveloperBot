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

have_claude_login() {
  # Claude stores subscription auth under ~/.claude after `claude` login.
  [[ -f "$CLAUDE_CREDS" ]] || grep -rqs "oauth" "$CLAUDE_CONFIG_DIR" 2>/dev/null
}

have_telegram_token() {
  [[ -f "$TELEGRAM_ENV" ]] && grep -qs "TELEGRAM_BOT_TOKEN=..*" "$TELEGRAM_ENV"
}

if ! have_claude_login || ! have_telegram_token; then
  echo "[claude-telegram] Setup not finished yet (Claude login and/or Telegram token missing)."
  echo "[claude-telegram] Waiting — will start automatically once setup is complete."
  # Exit non-zero so systemd restarts us after RestartSec, polling for setup.
  exit 1
fi

cd "$PROJECTS_DIR" || exit 1

# --dangerously-skip-permissions enables hands-off Telegram operation. Safe only
# because the box is locked down to the owner (see hardening in bootstrap.sh).
exec claude \
  --channels "$TELEGRAM_CHANNEL" \
  --dangerously-skip-permissions
