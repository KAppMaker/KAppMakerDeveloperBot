#!/usr/bin/env bash
# kappmaker-agents-install — register the specialist subagents so Claude Code
# can actually see them.
#
# THE BUG THIS FIXES: Claude Code discovers subagents in exactly two places —
# `<session root>/.claude/agents/` and `~/.claude/agents/`. On a box the
# always-on session's root is `~/projects` (app1) or `~/workspaces/appN` (extra
# workers), but `kapp-loop-install` writes the agents into the APP's folder:
# `~/projects/<App>/.claude/agents/`. That is one level below the session root,
# so none of them were ever registered and Claude reported:
#
#   "Project specialist agents aren't registered at this session's root, so I'll
#    have general-purpose agents load the specialist personas from their files."
#
# It still did the work, but as a generic agent reading a persona file — slower,
# and only when the owner remembered to point at the guidelines by hand.
#
# USER SCOPE is the right fix here, not the session root: every worker has a
# DIFFERENT root (~/workspaces/app2, app3, …), so per-root installs would need
# repeating for each one. `~/.claude/agents/` covers every session on the box.
#
# Safe to re-run; existing files are overwritten with the current versions.

set -uo pipefail

BASE_URL="${AGENTS_BASE_URL:-https://raw.githubusercontent.com/KAppMaker/KAppMakerDeveloperBot/main/templates/loop/.claude/agents}"
DEST="$HOME/.claude/agents"
AGENTS="orchestrator qa-engineer ui-ux-reviewer design-fidelity-reviewer onboarding-specialist paywall-conversion-specialist growth-virality-specialist delight-specialist"

log()  { printf '\033[32m[agents]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[agents]\033[0m %s\n' "$*" >&2; }

if [[ "${1:-}" == "--check" ]]; then
  n=$(ls "$DEST"/*.md 2>/dev/null | wc -l | tr -d ' ')
  log "$n specialist agents registered in $DEST"
  ls "$DEST"/*.md 2>/dev/null | sed 's|.*/|  · |'
  exit 0
fi

mkdir -p "$DEST"

installed=0
for a in $AGENTS; do
  tmp="$(mktemp)"
  if curl -fsSL "$BASE_URL/$a.md" -o "$tmp" && head -1 "$tmp" | grep -q -- '---'; then
    install -m 644 "$tmp" "$DEST/$a.md"
    installed=$((installed + 1))
  else
    warn "could not fetch $a"
  fi
  rm -f "$tmp"
done

log "registered $installed specialist agents in ~/.claude/agents"
log "Restart the always-on bot for a running session to pick them up."
