#!/usr/bin/env bash
# kappmaker-claude-mem-install — persistent memory across Claude Code sessions.
#
# claude-mem (Apache-2.0, thedotmack) captures what the agent does, compresses it,
# and injects the relevant parts back into later sessions. On an always-on box
# that matters more than on a laptop: the bot is restarted by systemd on OOM, on
# reboot and on every deploy, and without this each restart begins amnesiac.
#
# It installs as a Claude Code PLUGIN (enabledPlugins in ~/.claude/settings.json),
# NOT as a settings hook — so it coexists with the Stop hook that writes
# ~/.claude/session-history.md. Both are kept: session-history is the cheap
# always-there crash recovery, claude-mem is the richer recall.
#
# Costs the owner should know about, and why this is opt-in per box rather than
# silently on:
#   - Compression runs through the Claude Agent SDK, so it spends the customer's
#     own Claude subscription usage.
#   - It runs a worker process and stores vectors under ~/.claude-mem.
# Everything stays on the box: nothing is sent to KAppMaker.
#
# Usage:  kappmaker-claude-mem-install         (install + enable)
#         kappmaker-claude-mem-install --check (report status only)

set -uo pipefail

MARKER="$HOME/.config/kappmaker/.claude-mem-installed"
SETTINGS="$HOME/.claude/settings.json"

log()  { printf '\033[32m[claude-mem]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[claude-mem]\033[0m %s\n' "$*" >&2; }

installed() {
  grep -q '"claude-mem@' "$SETTINGS" 2>/dev/null
}

if [[ "${1:-}" == "--check" ]]; then
  if installed; then
    log "enabled (storage: $(du -sh "$HOME/.claude-mem" 2>/dev/null | cut -f1 || echo n/a))"
  else
    log "not installed"
  fi
  exit 0
fi

command -v npx >/dev/null || { warn "npx missing — skipping"; exit 0; }

if installed; then
  log "already enabled — nothing to do"
  exit 0
fi

# Keep a copy: the installer edits settings.json, and that file also carries the
# Telegram channel plugin and the session-history Stop hook.
if [[ -f "$SETTINGS" ]]; then
  cp "$SETTINGS" "$SETTINGS.pre-claude-mem" 2>/dev/null || true
fi

log "Installing (this pulls the package on first run)…"
if ! CI=1 timeout 600 npx --yes claude-mem@latest install --yes >/tmp/claude-mem-install.log 2>&1; then
  warn "install failed — see /tmp/claude-mem-install.log (the box works fine without it)"
  exit 0
fi

# Prove the things we care about survived.
if ! grep -q 'claude-history' "$SETTINGS" 2>/dev/null; then
  warn "the session-history Stop hook is missing after install — restoring settings"
  [[ -f "$SETTINGS.pre-claude-mem" ]] && cp "$SETTINGS.pre-claude-mem" "$SETTINGS"
  warn "claude-mem left disabled to protect crash recovery"
  exit 0
fi

if installed; then
  mkdir -p "$(dirname "$MARKER")" && touch "$MARKER"
  log "Enabled. Memory is injected from the session AFTER next — restart the bot to load it."
else
  warn "installer reported success but the plugin is not enabled; leaving as-is"
fi
