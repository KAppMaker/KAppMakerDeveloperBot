#!/usr/bin/env bash
# kappmaker-board-install — install (or repair) the read-only project board.
#
# bootstrap.sh calls this on new boxes. Boxes provisioned before the board
# existed run it once by hand:
#
#   curl -fsSL https://raw.githubusercontent.com/KAppMaker/KAppMakerDeveloperBot/main/provision/board-install.sh | sudo bash
#
# It installs files only. Nothing is started and no port is touched — the board
# stays off until the owner asks for it (`kappmaker-board link`).
#
# Idempotent: safe to re-run to pick up a newer board.

set -euo pipefail

DEVUSER="${DEVUSER:-devuser}"
PROVISION_BASE_URL="${PROVISION_BASE_URL:-https://raw.githubusercontent.com/KAppMaker/KAppMakerDeveloperBot/main/provision}"
TEMPLATE_BASE_URL="${TEMPLATE_BASE_URL:-https://raw.githubusercontent.com/KAppMaker/KAppMakerDeveloperBot/main/templates}"
HOME_DIR="/home/$DEVUSER"
CLAUDE_MD="$HOME_DIR/projects/CLAUDE.md"
MARKER="<!-- kappmaker-board-rules -->"

log()  { printf '\033[32m[board]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[board]\033[0m %s\n' "$*" >&2; }

[[ "$(id -u)" -eq 0 ]] || { echo "run me with sudo" >&2; exit 1; }
id "$DEVUSER" >/dev/null 2>&1 || { echo "no such user: $DEVUSER" >&2; exit 1; }

command -v node >/dev/null || { echo "node is missing — this box predates the board's requirements" >&2; exit 1; }
command -v cloudflared >/dev/null || warn "cloudflared missing — the board cannot be published until it is installed"

fetch() {   # fetch <url-path> <dest> [mode]
  local tmp; tmp="$(mktemp)"
  if curl -fsSL "$PROVISION_BASE_URL/$1" -o "$tmp"; then
    install -m "${3:-644}" "$tmp" "$2"
    rm -f "$tmp"
  else
    rm -f "$tmp"
    return 1
  fi
}

log "Installing the board server + UI"
install -d -o "$DEVUSER" -g "$DEVUSER" -m 755 "$HOME_DIR/bin"
fetch board-server.mjs "$HOME_DIR/bin/board-server.mjs" 755
fetch board.html       "$HOME_DIR/bin/board.html"       644
chown "$DEVUSER:$DEVUSER" "$HOME_DIR/bin/board-server.mjs" "$HOME_DIR/bin/board.html"

# State dir must exist before the unit starts: the service runs with the home
# directory replaced by a read-only tmpfs, so it cannot create this itself.
install -d -o "$DEVUSER" -g "$DEVUSER" -m 700 "$HOME_DIR/.local/state/kappmaker-board"
install -d -o "$DEVUSER" -g "$DEVUSER" -m 755 "$HOME_DIR/.config/kappmaker/bots"

log "Installing units (left disabled — the board ships off)"
for unit in kappmaker-board.service kappmaker-board-tunnel.service \
            kappmaker-board-idle.service kappmaker-board-idle.timer; do
  tmp="$(mktemp)"
  if curl -fsSL "$PROVISION_BASE_URL/$unit" -o "$tmp"; then
    sed "s/__DEVUSER__/$DEVUSER/g" "$tmp" > "/etc/systemd/system/$unit"
    chmod 644 "/etc/systemd/system/$unit"
  else
    warn "could not fetch $unit"
  fi
  rm -f "$tmp"
done

log "Installing the kappmaker-board command"
fetch board.sh /usr/local/bin/kappmaker-board 755

systemctl daemon-reload

# Teach the agent the rules the board depends on. On boxes provisioned before
# the board, ~/projects/CLAUDE.md predates these rules and may carry the
# owner's own edits — so APPEND behind a marker, never overwrite.
if [[ -f "$CLAUDE_MD" ]] && ! grep -qF "$MARKER" "$CLAUDE_MD"; then
  tmp="$(mktemp)"
  if curl -fsSL "$TEMPLATE_BASE_URL/projects-CLAUDE-board.md" -o "$tmp"; then
    log "Adding the project-board rules to ~/projects/CLAUDE.md"
    { printf '\n'; cat "$tmp"; } >> "$CLAUDE_MD"
    chown "$DEVUSER:$DEVUSER" "$CLAUDE_MD"
  else
    warn "could not fetch the board rules — the board will still work, but progress files may go stale"
  fi
  rm -f "$tmp"
fi

log "Done. The board is installed and OFF."
log "Ask your bot for your board, or run: kappmaker-board link"
