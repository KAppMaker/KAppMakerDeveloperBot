#!/usr/bin/env bash
# Always-on Claude + Telegram runner for an ADDITIONAL worker (app2, app3, …).
# Managed by systemd template: claude-telegram@app2.service.
#
# The FIRST worker (app1) keeps its own dedicated runner + unit
# (claude-telegram-run.sh / claude-telegram.service) — that path is the
# verified single-bot flow and is deliberately left untouched.
#
# Extra workers let a customer build several apps in parallel: each has its own
# Telegram bot and its own Claude session, all sharing one Claude login and one
# ~/projects folder. See docs/MULTI_BOT.md in the KAppMaker-AI repo for the
# findings this script encodes — every non-obvious line below traces to one.
#
# ZERO-KNOWLEDGE: the bot token is created by the customer and lives only in
# this box's state dir. This script checks for its presence, never reads it out.

set -uo pipefail

INSTANCE="${1:-}"
if [[ ! "$INSTANCE" =~ ^app[1-9][0-9]?$ ]]; then
  echo "usage: $(basename "$0") app2|app3|…" >&2
  exit 64
fi

SESSION="claude-$INSTANCE"
BOOT_DIR="$HOME/workspaces/$INSTANCE"
STATE_DIR="$HOME/.claude/channels/telegram-$INSTANCE"
TELEGRAM_CHANNEL="plugin:telegram@claude-plugins-official"
PROJECTS_DIR="$HOME/projects"
KAPP_ENV="$HOME/.config/kappmaker/env"
AUTH_CACHE="$HOME/.claude/mcp-needs-auth-cache.json"
BOT_SENT_MARKER="$STATE_DIR/.bot-username-sent"

# shellcheck disable=SC1090
[[ -f "$KAPP_ENV" ]] && source "$KAPP_ENV"

have_claude_login() {
  # Authoritative check. Do NOT grep ~/.claude for "oauth" — the channel
  # plugin's node_modules match it and give a false positive.
  claude auth status 2>/dev/null | grep -q '"loggedIn" *: *true'
}

have_telegram_token() {
  [[ -f "$STATE_DIR/.env" ]] && grep -qs "TELEGRAM_BOT_TOKEN=..*" "$STATE_DIR/.env"
}

if ! have_claude_login || ! have_telegram_token; then
  echo "[$SESSION] Waiting: Claude login and/or this worker's bot token is missing."
  # Non-zero so systemd retries after RestartSec (polling for setup).
  exit 1
fi

# FINDING: Claude Code runs the channel plugin's MCP server as a singleton keyed
# by the session's start directory. Two sessions started from the SAME directory
# share one server and the second bot never polls. So every worker needs its own
# boot dir. Nothing is stored there — real work happens in ~/projects.
mkdir -p "$BOOT_DIR"

# The boot dir's CLAUDE.md orients the session. Shared conventions are INLINED
# rather than "@"-imported: an @import pointing outside the boot dir triggers a
# one-time interactive "allow external imports?" prompt, which a headless box
# has nobody to answer.
write_boot_claude_md() {
  {
    cat <<EOF
# Always-on worker ($INSTANCE)

This directory is only this session's boot folder — NEVER create or store
anything here.

All projects live in **$PROJECTS_DIR/**.
- Existing project: cd $PROJECTS_DIR/<name> and work there.
- NEW project: create it as $PROJECTS_DIR/<name> — never in this boot folder.

## You are not alone on this machine

Other always-on workers share this projects folder and CANNOT see your session.
Two agents editing one project at the same time corrupts work, so there is a
shared status board. You are worker \`$INSTANCE\`.

When the user puts you on a project, record it:

\`\`\`bash
kappmaker-claim take $INSTANCE <project>
\`\`\`

This never blocks you. If it reports that another helper was already on that
project, do not silently carry on — say so in plain words and ask the user
whether to continue or leave it to the other one. Follow their answer; they can
see things you cannot.

When the user says a project is done, or moves you elsewhere:

\`\`\`bash
kappmaker-claim release $INSTANCE <project>
\`\`\`

\`kappmaker-claim list\` shows the whole board — use it whenever the user asks
who is working on what. The board can be out of date (a helper may have been
restarted mid-task), so treat it as a hint, never as proof.
EOF

    # Inline the shared conventions + memory so every worker starts with the
    # same context the first bot has.
    for shared in "$PROJECTS_DIR/CLAUDE.md" "$PROJECTS_DIR/MEMORY.md"; do
      if [[ -f "$shared" ]]; then
        printf '\n---\n\n# Shared: %s\n\n' "$(basename "$shared")"
        cat "$shared"
      fi
    done
  } > "$BOOT_DIR/CLAUDE.md"
}

write_boot_claude_md

# FINDING: a failed channel connect is cached in mcp-needs-auth-cache.json and
# NEVER retried — later sessions skip the channel silently while still printing
# the "channels active" banner. Drop this worker's stale entry before starting
# so a fixed cause actually takes effect.
if [[ -f "$AUTH_CACHE" ]]; then
  python3 - "$AUTH_CACHE" <<'PY' 2>/dev/null || true
import json, sys
p = sys.argv[1]
try:
    with open(p) as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
if data.pop("plugin:telegram:telegram", None) is not None:
    with open(p, "w") as f:
        json.dump(data, f)
PY
fi

# Report this worker's PUBLIC bot handle to the control plane (dashboard deep
# link). state=progress so a secondary worker never re-drives box lifecycle.
# The token itself never leaves the box: read in pure bash (ps-safe) and only
# the resulting @handle is sent.
report_bot_username() {
  # The handle file is also read by the project board (which cannot see this
  # worker's channel dir, where the token lives), so resolve the @handle even
  # when there is nothing to report to — e.g. a box with no control plane.
  local handle_file="$HOME/.config/kappmaker/bots/$INSTANCE"
  if [[ -s "$handle_file" && -f "$BOT_SENT_MARKER" ]]; then
    return 0
  fi

  local tg_token="" line bot_username=""
  while IFS= read -r line; do
    case "$line" in
      TELEGRAM_BOT_TOKEN=*)
        tg_token="${line#TELEGRAM_BOT_TOKEN=}"
        tg_token="${tg_token%\"}"; tg_token="${tg_token#\"}"
        break;;
    esac
  done < "$STATE_DIR/.env"

  [[ -n "$tg_token" ]] || return 0

  bot_username="$(curl -fsS --max-time 10 "https://api.telegram.org/bot${tg_token}/getMe" 2>/dev/null \
    | sed -n 's/.*"username":"\([A-Za-z0-9_]*\)".*/\1/p')"
  unset tg_token

  [[ -n "$bot_username" ]] || return 0

  mkdir -p "$(dirname "$handle_file")"
  printf '%s\n' "$bot_username" > "$handle_file"
  chmod 644 "$handle_file"

  [[ -n "${SERVER_CALLBACK_URL:-}" && ! -f "$BOT_SENT_MARKER" ]] || return 0

  if curl -fsS -X POST "$SERVER_CALLBACK_URL" \
      --data-urlencode "state=progress" \
      --data-urlencode "workspace=$INSTANCE" \
      --data-urlencode "bot_username=$bot_username" \
      >/dev/null 2>&1; then
    touch "$BOT_SENT_MARKER"
  fi
}

report_bot_username

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "[$SESSION] Already running — supervising."
else
  # Two findings in this one command:
  #  - bun must be on PATH: the channel server runs on it, and under a bare
  #    systemd/tmux environment it is not found (the failure is silent, see the
  #    auth-cache note above).
  #  - env vars must go INSIDE the command string: tmux commands inherit the
  #    tmux SERVER's environment, not this shell's.
  tmux new-session -d -s "$SESSION" -c "$BOOT_DIR" \
    "PATH=$HOME/.bun/bin:\$PATH TELEGRAM_STATE_DIR=$STATE_DIR claude --channels $TELEGRAM_CHANNEL --dangerously-skip-permissions"
fi

# Supervise the session: exiting non-zero makes systemd restart us, which
# re-creates the session. Also keeps `tmux attach -t claude-appN` working for
# the owner over SSH.
while tmux has-session -t "$SESSION" 2>/dev/null; do
  sleep 5
done

echo "[$SESSION] Session ended — systemd will restart it."
exit 1
