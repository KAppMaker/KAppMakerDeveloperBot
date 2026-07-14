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
TELEGRAM_ACCESS="$TELEGRAM_DIR/access.json"
TELEGRAM_APPROVED="$TELEGRAM_DIR/approved"
TELEGRAM_CHANNEL="plugin:telegram@claude-plugins-official"

# Signed, secret-free control-plane callback URL (persisted by bootstrap.sh).
# Sourced so this wizard can report setup_complete once pairing succeeds.
KAPP_ENV="$HOME/.config/kappmaker/env"
# shellcheck disable=SC1090
[[ -f "$KAPP_ENV" ]] && source "$KAPP_ENV"

BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
CYAN=$'\033[1;36m'; GREEN=$'\033[1;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'

say()  { printf '%s\n' "$*"; }
step() { printf '\n%s%s%s\n\n' "$CYAN" "$*" "$RESET"; }
ok()   { printf '%s✓ %s%s\n' "$GREEN" "$*" "$RESET"; }
oops() { printf '%s✗ %s%s\n' "$RED" "$*" "$RESET"; }

trap 'printf "\n%sSetup paused — just reload this page to pick up where you left off.%s\n" "$YELLOW" "$RESET"; exit 130' INT

# Same detection logic as claude-telegram-run.sh — keep the three in sync.
# Authoritative check via `claude auth status` (NOT a recursive grep for "oauth",
# which matches the Telegram plugin's node_modules and would falsely report
# "signed in", skipping Step 1). Version-proof — doesn't assume a creds path.
have_claude_login()   { claude auth status 2>/dev/null | grep -q '"loggedIn" *: *true'; }
have_telegram_token() { [[ -f "$TELEGRAM_ENV" ]] && grep -qs "TELEGRAM_BOT_TOKEN=..*" "$TELEGRAM_ENV"; }
# Paired = the customer's Telegram account is on the allowlist. Until then the
# bot only hands out pairing codes; nobody can reach the assistant.
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

# trim surrounding whitespace from $1
trim() { local s="$1"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

# Look up the bot's @username from the stored token (public info only).
fetch_bot_username() {
  local tok="" line
  while IFS= read -r line; do
    case "$line" in
      TELEGRAM_BOT_TOKEN=*) tok="${line#TELEGRAM_BOT_TOKEN=}"; tok="${tok%\"}"; tok="${tok#\"}"; break;;
    esac
  done < "$TELEGRAM_ENV" 2>/dev/null
  [[ -n "$tok" ]] || return 0
  curl -fsS --max-time 10 "https://api.telegram.org/bot${tok}/getMe" 2>/dev/null \
    | sed -n 's/.*"username":"\([A-Za-z0-9_]*\)".*/\1/p'
}

# Approve one pairing code the customer just received on Telegram. This is the
# exact same edit /telegram:access performs: move the pending code's sender ID
# into allowFrom, drop the pending entry, drop an approved/<id> file (the server
# polls it to send "you're in"), and lock the DM policy to allowlist so nobody
# else can even request a code. Prints OK / NOTFOUND / EXPIRED / ERROR.
#
# SECURITY: we approve ONLY the specific code the customer types (the one their
# own Telegram account was handed). We never auto-pick a pending entry — that is
# exactly what a squatting attacker who DM'd the bot would need. The code is
# entered by the box owner in their own basic-auth-gated terminal.
pair_code() {
  local code; code="$(trim "$1")"
  [[ -n "$code" ]] || { printf 'ERROR'; return; }
  python3 - "$TELEGRAM_ACCESS" "$TELEGRAM_APPROVED" "$code" <<'PY' 2>/dev/null || printf 'ERROR'
import json, os, sys, time
access_file, approved_dir, code = sys.argv[1], sys.argv[2], sys.argv[3].strip()
try:
    a = json.load(open(access_file))
except Exception:
    a = {}
a.setdefault("dmPolicy", "pairing"); a.setdefault("allowFrom", [])
a.setdefault("groups", {}); a.setdefault("pending", {})
pending = a.get("pending", {})
# Case-insensitive match on the 6-char code.
key = None
for k in pending:
    if k.lower() == code.lower():
        key = k; break
if key is None:
    print("NOTFOUND"); sys.exit(0)
entry = pending[key]
exp = entry.get("expiresAt")
if exp and float(exp) < time.time() * 1000:
    del pending[key]
    json.dump(a, open(access_file, "w"), indent=2)
    print("EXPIRED"); sys.exit(0)
sid = str(entry.get("senderId", "")); cid = str(entry.get("chatId", sid))
if sid and sid not in a["allowFrom"]:
    a["allowFrom"].append(sid)
del pending[key]
a["dmPolicy"] = "allowlist"          # lock down: only the allowlist can reach the bot
json.dump(a, open(access_file, "w"), indent=2)
os.makedirs(approved_dir, exist_ok=True)
if sid:
    open(os.path.join(approved_dir, sid), "w").write(cid)   # server polls this → "you're in"
print("OK", sid); sys.exit(0)
PY
}

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
say "Three quick steps and it starts working for you — takes about 3 minutes."
say ""
say "${DIM}(Tip: keep this tab open; you'll hop to another tab and come back.)${RESET}"

if have_claude_login && have_telegram_token && have_paired; then
  step "You're already set up! 🎉"
  say "Your bot is running. Open Telegram and send it a message."
  say "You can close this page."
  exit 0
fi

# ---------- Step 1: Claude login ----------
step "Step 1 of 3 — Sign in to Claude"

if have_claude_login; then
  ok "Already signed in to Claude — nothing to do here."
else
  say "Your machine uses ${BOLD}your${RESET} Claude subscription to build your app."
  say "Here's how the sign-in works:"
  say ""
  say "  1. I'll start the Claude sign-in below. It will show a ${BOLD}link${RESET}."
  say "  2. Click the link (or copy it into a new browser tab) and sign in."
  say "  3. Copy the code you get and paste it back here, then press Enter."
  say ""
  while ! have_claude_login; do
    printf '%s' "${BOLD}Press Enter to start the Claude sign-in… ${RESET}"
    read -r _ || exit 0
    say ""
    # `claude auth login` runs the sign-in flow directly (prints the URL, waits
    # for the pasted code) — no interactive chat screen to /exit out of. Run from
    # the projects workspace so Claude's first run lands where the always-on bot
    # works later. --claudeai = use the Claude subscription (not API billing).
    ( cd "$HOME/projects" 2>/dev/null || cd "$HOME" || exit 1; claude auth login --claudeai ) || true
    say ""
    if have_claude_login; then
      ok "Signed in to Claude!"
    else
      oops "Hmm, I don't see a Claude sign-in yet. No worries — let's try again."
    fi
  done
fi

# ---------- Step 2: Telegram bot token ----------
step "Step 2 of 3 — Add your Telegram bot"

# Tracks whether we saved the token in THIS run (so we only bounce the always-on
# service once, right after saving — not on every page reload).
JUST_SAVED_TOKEN=0
BOT_USERNAME=""

if have_telegram_token; then
  ok "Telegram bot token already saved — nothing to do here."
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
    # NO quotes around the value: the Telegram plugin's .env parser is a plain
    # /^(\w+)=(.*)$/ that keeps surrounding quotes verbatim, so a quoted token
    # becomes bot"123:ABC"/getMe → 404 and the bot never polls. (This matches the
    # official /telegram:configure skill, which also writes it unquoted.)
    printf 'TELEGRAM_BOT_TOKEN=%s\n' "$token" > "$TELEGRAM_ENV"
    umask 022
    chmod 600 "$TELEGRAM_ENV"
    unset token
    JUST_SAVED_TOKEN=1

    ok "Token saved — found your bot ${BOLD}@${BOT_USERNAME:-your_bot}${RESET}${GREEN}.${RESET}"
    say "   One more step and you'll be able to talk to it."
  done
fi

# Recover the bot username if Step 2 was skipped (token already on disk from an
# earlier run) — needed for the "message @yourbot" instructions below.
[[ -z "$BOT_USERNAME" ]] && BOT_USERNAME="$(fetch_bot_username)"

# ---------- Step 3: pair your Telegram account ----------
step "Step 3 of 3 — Connect your account to the bot"

if have_paired; then
  ok "Your Telegram account is already paired — nothing to do here."
else
  # Bring the bot ONLINE so it can hand out a pairing code. The always-on
  # service runs `claude --channels telegram`; once the token exists it starts
  # the bot but leaves it locked (nobody on the allowlist yet). Bounce it now if
  # we just saved the token, otherwise just make sure it's started.
  say "${DIM}Waking up your bot… (about 15 seconds)${RESET}"
  if [[ "$JUST_SAVED_TOKEN" == "1" ]]; then
    sudo -n systemctl restart claude-telegram.service >/dev/null 2>&1 || true
  else
    sudo -n systemctl start claude-telegram.service >/dev/null 2>&1 || true
  fi
  sleep 12

  say ""
  say "Last step — so that ${BOLD}only you${RESET} can talk to your bot:"
  say ""
  say "  1. Open Telegram and find your bot: ${BOLD}@${BOT_USERNAME:-your_bot}${RESET}"
  say "  2. Send it any message — for example, ${BOLD}hi${RESET}"
  say "  3. It replies with a ${BOLD}6-character code${RESET}."
  say "  4. Type that code below and press Enter."
  say ""
  say "${DIM}(If it doesn't reply within a few seconds, wait a moment and send it"
  say "another message — the bot is still starting up.)${RESET}"
  say ""

  while ! have_paired; do
    printf '%s' "${BOLD}Enter the 6-character code your bot sent you: ${RESET}"
    IFS= read -r code || exit 0
    code="$(trim "$code")"
    [[ -z "$code" ]] && continue

    case "$(pair_code "$code")" in
      OK*)
        ok "Paired! Your bot now answers only to you. 🔒"
        ;;
      NOTFOUND)
        oops "I don't see that code yet."
        say "   Make sure you messaged ${BOLD}@${BOT_USERNAME:-your bot}${RESET} and it replied with a code,"
        say "   then paste the code here. (Give it a few seconds after your first message.)"
        ;;
      EXPIRED)
        oops "That code expired."
        say "   Send your bot another message to get a fresh code, then paste it here."
        ;;
      *)
        oops "Couldn't pair with that code — double-check it and try again."
        ;;
    esac
  done
fi

# ---------- Done ----------
step "That's it — you're all set! 🎉"
say "  ${BOLD}Open Telegram, message @${BOT_USERNAME:-your bot}, and say hi.${RESET}"
say "  It will introduce itself and ask about the app you want to build."
say ""
say "${DIM}This setup page is switching itself off now — that's normal and means"
say "everything worked. You can close this tab.${RESET}"
say ""

# Tell the control plane setup is complete (flips the dashboard to Active),
# carrying only the PUBLIC bot username — never the token. One-shot via the same
# marker the always-on runner uses, so the two never double-report.
SETUP_SENT_MARKER="$HOME/.config/kappmaker/.setup-complete-sent"
if [[ -n "${SERVER_CALLBACK_URL:-}" && ! -f "$SETUP_SENT_MARKER" ]]; then
  if curl -fsS --max-time 15 -X POST "$SERVER_CALLBACK_URL" \
      --data-urlencode "state=setup_complete" \
      --data-urlencode "message=customer setup complete" \
      ${BOT_USERNAME:+--data-urlencode "bot_username=$BOT_USERNAME"} \
      >/dev/null 2>&1; then
    mkdir -p "$(dirname "$SETUP_SENT_MARKER")" && touch "$SETUP_SENT_MARKER"
  fi
fi

# Shut the setup page down IMMEDIATELY, so this terminal doesn't respawn (ttyd
# would otherwise re-run the wizard on the browser's auto-reconnect, looking
# like an endless refresh loop). Run the teardown in a detached transient unit:
# stopping setup-web kills this wizard's process tree, so the teardown must live
# outside it to finish. The always-on bot is already running (started above), so
# we no longer restart it here. devuser has passwordless sudo.
sudo -n systemd-run --quiet --collect --unit kappmaker-finish-setup \
  /bin/bash -c 'sleep 2; /usr/local/bin/kappmaker-setup-teardown' \
  2>/dev/null \
  || sudo -n /bin/bash -c '( sleep 2; /usr/local/bin/kappmaker-setup-teardown ) >/dev/null 2>&1 &' 2>/dev/null \
  || true

exit 0
