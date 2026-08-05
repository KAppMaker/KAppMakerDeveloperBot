#!/usr/bin/env bash
# kappmaker-add-bot — add another always-on worker (its own Telegram bot) so the
# customer can build several apps in parallel.
#
# Runs as the box owner, either from the browser setup terminal or over SSH.
# Safe to re-run: every step skips itself once done.
#
# ZERO-KNOWLEDGE: the new bot's token is typed HERE, on the customer's own box,
# and never leaves it. Only the PUBLIC @handle is later reported to the
# dashboard (by claude-telegram-worker.sh) so the "open your bot" link works.

set -uo pipefail

export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

PRIMARY_STATE="$HOME/.claude/channels/telegram"
KAPP_ENV="$HOME/.config/kappmaker/env"
# shellcheck disable=SC1090
[[ -f "$KAPP_ENV" ]] && source "$KAPP_ENV"

# How many workers this box's tier allows. Written by bootstrap.sh from the
# control plane; a box that somehow lacks it stays at one bot.
MAX_BOTS="${KAPP_MAX_BOTS:-1}"

BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
CYAN=$'\033[1;36m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'

say()  { printf '%s\n' "$*"; }
step() { printf '\n%s%s%s\n\n' "$CYAN" "$*" "$RESET"; }
ok()   { printf '%s✓ %s%s\n' "$GREEN" "$*" "$RESET"; }
oops() { printf '%s✗ %s%s\n' "$RED" "$*" "$RESET"; }

trap 'printf "\n%sStopped. Nothing was changed — run kappmaker-add-bot again any time.%s\n" "$YELLOW" "$RESET"; exit 130' INT

worker_exists() { [[ -f "$HOME/.claude/channels/telegram-$1/.env" ]]; }

# app1 is the box's first bot (its own service). Extra workers start at app2.
next_instance() {
  local i
  for ((i = 2; i <= MAX_BOTS; i++)); do
    worker_exists "app$i" || { echo "app$i"; return 0; }
  done
  return 1
}

count_active() {
  local n=1 i
  for ((i = 2; i <= MAX_BOTS; i++)); do
    worker_exists "app$i" && n=$((n + 1))
  done
  echo "$n"
}

step "Add another helper"

if [[ "$MAX_BOTS" -lt 2 ]]; then
  oops "Your plan includes one helper."
  say ""
  say "Upgrade your plan to run several apps at the same time — each extra"
  say "helper gets its own chat, and they work in parallel."
  exit 1
fi

INSTANCE="$(next_instance)" || {
  oops "You're already using all $MAX_BOTS helpers your plan includes."
  say ""
  say "To reuse one, ask that helper to finish up, or upgrade your plan."
  exit 1
}

ACTIVE="$(count_active)"
STATE_DIR="$HOME/.claude/channels/telegram-$INSTANCE"

say "You have ${BOLD}$ACTIVE of $MAX_BOTS${RESET} helpers running."
say "Let's set up helper number $((ACTIVE + 1)). Takes about a minute."

step "Step 1 — create a new bot in Telegram"

say "In Telegram, open ${BOLD}@BotFather${RESET} and send:"
say ""
say "    ${BOLD}/newbot${RESET}"
say ""
say "It asks for a name (anything you like, e.g. \"My Second App\") and then a"
say "username that must end in ${BOLD}bot${RESET}. When you're done it replies with a long"
say "token that looks like ${DIM}123456789:AAH...${RESET}"
say ""

TOKEN=""
while :; do
  printf '%sPaste the token here (it stays on your machine): %s' "$BOLD" "$RESET"
  # -r: keep backslashes verbatim. Not -s: a silent paste is confusing for
  # non-technical customers, and this is their own private box terminal.
  IFS= read -r TOKEN || { oops "No input — run kappmaker-add-bot again."; exit 1; }
  TOKEN="${TOKEN//[[:space:]]/}"

  [[ -z "$TOKEN" ]] && { oops "Nothing pasted — try again."; continue; }

  printf '\n%sChecking that token…%s\n' "$DIM" "$RESET"
  BOT_USERNAME="$(curl -fsS --max-time 15 "https://api.telegram.org/bot${TOKEN}/getMe" 2>/dev/null \
    | sed -n 's/.*"username":"\([A-Za-z0-9_]*\)".*/\1/p')"

  if [[ -n "$BOT_USERNAME" ]]; then
    ok "Connected to @$BOT_USERNAME"
    # Publish the PUBLIC handle where the project board can read it. The board
    # cannot see this helper's channel dir (that is where the token lives), so
    # without this file it would show the bot with no way to open its chat.
    install -d -m 755 "$HOME/.config/kappmaker/bots"
    printf '%s\n' "$BOT_USERNAME" > "$HOME/.config/kappmaker/bots/$INSTANCE"
    chmod 644 "$HOME/.config/kappmaker/bots/$INSTANCE"
    break
  fi

  oops "Telegram didn't accept that token."
  say "  Copy the whole line BotFather sent, with nothing before or after it."
done

step "Step 2 — starting your new helper"

install -d -m 700 "$STATE_DIR"

# The token MUST be written unquoted: a quoted value makes the Telegram library
# call getMe with quotes in the URL, which 404s and the bot never polls.
printf 'TELEGRAM_BOT_TOKEN=%s\n' "$TOKEN" > "$STATE_DIR/.env"
chmod 600 "$STATE_DIR/.env"
unset TOKEN

# Carry the pairing allowlist over from the first bot: the owner is already
# approved there, so the new bot is reachable by them immediately and by nobody
# else. This is why extra bots need no pairing dance.
if [[ -f "$PRIMARY_STATE/access.json" ]]; then
  cp "$PRIMARY_STATE/access.json" "$STATE_DIR/access.json"
  chmod 600 "$STATE_DIR/access.json"
  ok "Only you can talk to it (copied from your first helper)"
else
  oops "Couldn't find your first helper's access list — finish the main setup first."
  exit 1
fi

# systemd template instance: claude-telegram@app2.service …
if sudo -n systemctl enable --now "claude-telegram@$INSTANCE.service" 2>/dev/null; then
  ok "Helper started, and it will come back on its own after a reboot"
else
  oops "Could not start the background service."
  say "  Try:  sudo systemctl enable --now claude-telegram@$INSTANCE.service"
  exit 1
fi

step "Step 3 — say hello"

say "Give it about half a minute to wake up, then open:"
say ""
say "    ${BOLD}https://t.me/$BOT_USERNAME${RESET}"
say ""
say "Send it a message like ${BOLD}\"what can you do?\"${RESET} to check it answers."
say ""
say "${BOLD}Working on several apps at once${RESET}"
say "  Each helper works on ONE project at a time so they never trip over each"
say "  other. Just tell this one which app to work on — it takes care of the rest."
say ""
say "${DIM}  Your projects folder is shared: $HOME/projects${RESET}"
say ""
ok "Helper $((ACTIVE + 1)) of $MAX_BOTS is ready."
