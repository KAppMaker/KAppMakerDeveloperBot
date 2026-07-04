#!/usr/bin/env bash
# KAppMaker AI — guided one-time setup wizard (runs INSIDE the browser terminal).
#
# Served by setup-web.service (ttyd, loopback-only) behind Caddy TLS — see
# bootstrap.sh. Runs as the box owner (devuser) and walks a NON-TECHNICAL
# customer through the two things only they can do:
#
#   1. log into their Claude subscription (OAuth link they click themselves),
#   2. connect their Telegram bot (token from @BotFather).
#
# The always-on claude-telegram service polls for these credentials every ~15s;
# as soon as both exist it starts the bot, reports setup_complete to the control
# plane, and tears the browser-setup terminal down for good (setup-teardown.sh).
#
# ZERO-KNOWLEDGE: the Claude credentials and the Telegram token are created
# HERE, on the customer's own box, and never leave it. This wizard only ever
# calls api.telegram.org (to verify the token the customer just typed).
#
# ttyd re-runs this script for every new browser connection, so it must be
# safe to run any number of times (every step skips itself once done).

set -uo pipefail

# ttyd starts us with a minimal environment; make sure the globally-installed
# `claude` (npm -g) and any user-local tools are findable.
export PATH="$HOME/bin:$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

CLAUDE_CREDS="$HOME/.claude/.credentials.json"
CLAUDE_CONFIG_DIR="$HOME/.claude"
TELEGRAM_DIR="$HOME/.claude/channels/telegram"
TELEGRAM_ENV="$TELEGRAM_DIR/.env"

BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
CYAN=$'\033[1;36m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'

say()  { printf '%s\n' "$*"; }
step() { printf '\n%s%s%s\n\n' "$CYAN" "$*" "$RESET"; }
ok()   { printf '%s✓ %s%s\n' "$GREEN" "$*" "$RESET"; }
oops() { printf '%s✗ %s%s\n' "$RED" "$*" "$RESET"; }

trap 'printf "\n%sSetup paused — just reload this page to pick up where you left off.%s\n" "$YELLOW" "$RESET"; exit 130' INT

# Same detection logic as claude-telegram-run.sh — keep the two in sync.
have_claude_login()   { [[ -f "$CLAUDE_CREDS" ]] || grep -rqs "oauth" "$CLAUDE_CONFIG_DIR" 2>/dev/null; }
have_telegram_token() { [[ -f "$TELEGRAM_ENV" ]] && grep -qs "TELEGRAM_BOT_TOKEN=..*" "$TELEGRAM_ENV"; }

clear 2>/dev/null || true
printf '%s' "$CYAN"
cat <<'BANNER'
  _  __  _                 __  __       _              _    ___
 | |/ / / \   _ __  _ __  |  \/  | __ _| | _____ _ __ / \  |_ _|
 | ' / / _ \ | '_ \| '_ \ | |\/| |/ _` | |/ / _ \ '__/ _ \  | |
 | . \/ ___ \| |_) | |_) || |  | | (_| |   <  __/ | / ___ \ | |
 |_|\_\_/  \_\ .__/| .__/ |_|  |_|\__,_|_|\_\___|_|/_/   \_\___|
             |_|   |_|
BANNER
printf '%s' "$RESET"
say ""
say "${BOLD}Welcome! This is your very own app-building machine.${RESET}"
say "Two quick steps and it starts working for you — takes about 3 minutes."
say ""
say "${DIM}(Tip: keep this tab open; you'll hop to another tab and come back.)${RESET}"

if have_claude_login && have_telegram_token; then
  step "You're already set up! 🎉"
  say "Your bot is running. Open Telegram and send it a message."
  say "You can close this page."
  exit 0
fi

# ---------- Step 1: Claude login ----------
step "Step 1 of 2 — Sign in to Claude"

if have_claude_login; then
  ok "Already signed in to Claude — nothing to do here."
else
  say "Your machine uses ${BOLD}your${RESET} Claude subscription to build your app."
  say "Here's how the sign-in works:"
  say ""
  say "  1. I'll start Claude below. It will show a ${BOLD}link${RESET}."
  say "  2. Click the link (or copy it into a new browser tab) and sign in."
  say "  3. Copy the code you get and paste it back here, then press Enter."
  say "  4. When you see Claude's chat screen, type ${BOLD}/exit${RESET} and press"
  say "     Enter to come back to me."
  say ""
  while ! have_claude_login; do
    printf '%s' "${BOLD}Press Enter to start the Claude sign-in… ${RESET}"
    read -r _ || exit 0
    say ""
    # Run from the projects workspace so Claude's first run lands where the
    # always-on bot will work later.
    ( cd "$HOME/projects" 2>/dev/null || cd "$HOME" || exit 1; claude ) || true
    say ""
    if have_claude_login; then
      ok "Signed in to Claude!"
    else
      oops "Hmm, I don't see a Claude sign-in yet. No worries — let's try again."
    fi
  done
fi

# ---------- Step 2: Telegram bot token ----------
step "Step 2 of 2 — Connect your Telegram bot"

if have_telegram_token; then
  ok "Telegram bot already connected — nothing to do here."
else
  say "Your app-builder talks to you through your own Telegram bot."
  say "If you don't have a bot token yet, here's how to get one (1 minute):"
  say ""
  say "  1. Open Telegram and search for ${BOLD}@BotFather${RESET} (blue checkmark)."
  say "  2. Send it the message: ${BOLD}/newbot${RESET}"
  say "  3. Follow its two questions (a name, then a username ending in 'bot')."
  say "  4. BotFather replies with a ${BOLD}token${RESET} that looks like:"
  say "     ${DIM}1234567890:AAHrX3…  (numbers, a colon, then letters)${RESET}"
  say ""
  BOT_USERNAME=""
  while ! have_telegram_token; do
    printf '%s' "${BOLD}Paste your bot token here and press Enter: ${RESET}"
    IFS= read -r token || exit 0
    # Trim surrounding whitespace (easy to pick up when copy-pasting).
    token="${token#"${token%%[![:space:]]*}"}"
    token="${token%"${token##*[![:space:]]}"}"

    if [[ -z "$token" ]]; then
      continue
    fi
    if [[ ! "$token" =~ ^[0-9]+:[A-Za-z0-9_-]{30,}$ ]]; then
      oops "That doesn't look like a bot token (expected numbers:letters, like 1234567890:AAH…)."
      say "   Double-check BotFather's message and paste the whole token."
      continue
    fi

    say "${DIM}Checking your token with Telegram…${RESET}"
    # curl --config on stdin keeps the token out of the process list (ps-safe).
    resp="$(curl -fsS --max-time 15 --config - 2>/dev/null <<CURLCFG
url = "https://api.telegram.org/bot${token}/getMe"
CURLCFG
)" || resp=""

    if [[ "$resp" != *'"ok":true'* ]]; then
      oops "Telegram didn't accept that token."
      say "   Make sure you copied the whole thing from BotFather, then try again."
      continue
    fi

    BOT_USERNAME="$(printf '%s' "$resp" | sed -n 's/.*"username":"\([A-Za-z0-9_]*\)".*/\1/p')"

    # Store it exactly where the always-on service (and the Telegram channel
    # plugin) expect it. 600: readable by this user only, never leaves the box.
    mkdir -p "$TELEGRAM_DIR"
    chmod 700 "$TELEGRAM_DIR" 2>/dev/null || true
    umask 177
    printf 'TELEGRAM_BOT_TOKEN="%s"\n' "$token" > "$TELEGRAM_ENV"
    umask 022
    chmod 600 "$TELEGRAM_ENV"
    unset token

    ok "Token verified — your bot ${BOLD}@${BOT_USERNAME:-your_bot}${RESET}${GREEN} is connected!${RESET}"
  done
fi

# ---------- Done ----------
step "That's it — you're done! 🎉"
say "Your machine is starting your bot right now (takes ~15 seconds)."
say ""
say "  ${BOLD}Next:${RESET} open Telegram, find ${BOLD}@${BOT_USERNAME:-your bot}${RESET}, and say hi."
say "  It will introduce itself and ask about the app you want to build."
say ""
say "${DIM}This setup page will switch itself off in a moment — that's normal"
say "and means everything worked. You can close this tab.${RESET}"
say ""
exit 0
