#!/usr/bin/env bash
# kappmaker-board — the owner's control over their project board.
#
# The board is a READ-ONLY view of ~/projects (checklists, git activity, and
# what each always-on worker is doing right now). It ships OFF: nothing is
# running and nothing is reachable until the owner asks for it.
#
# Reachability is an OUTBOUND Cloudflare tunnel, never an open port — `ufw`
# stays exactly as provisioning left it (SSH only) and a port scan of this box
# still finds nothing else. Same mechanism ~/bin/preview already uses.
#
# Access is a one-time link: `link` mints a single-use token that expires in
# 10 minutes and prints a URL. Opening it sets a 30-day session cookie in that
# browser. A link that has been used, or left sitting in a chat, is worthless.
#
# Usage:
#   kappmaker-board link         # turn it on if needed + print a fresh login link
#   kappmaker-board on           # start the board + tunnel
#   kappmaker-board off          # stop both — unreachable from anywhere again
#   kappmaker-board status       # what is running, and the current address
#   kappmaker-board logout-all   # end every signed-in browser session
#   kappmaker-board idle-check   # (timer) stop the board when nobody is looking

set -uo pipefail

STATE_DIR="${KAPP_BOARD_STATE:-$HOME/.local/state/kappmaker-board}"
TOKENS_DIR="$STATE_DIR/tokens"
TUNNEL_LOG="$STATE_DIR/tunnel.log"
BOARD_UNIT="kappmaker-board.service"
TUNNEL_UNIT="kappmaker-board-tunnel.service"
IDLE_HOURS="${KAPP_BOARD_IDLE_HOURS:-12}"
URL_RE='https://[a-zA-Z0-9][a-zA-Z0-9-]*\.trycloudflare\.com'

BOLD=$'\033[1m'; RESET=$'\033[0m'; GREEN=$'\033[32m'; DIM=$'\033[2m'

say()  { printf '%s\n' "$*"; }
fail() { printf '%s\n' "$*" >&2; exit 1; }

usage() { sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 64; }

sudo_n() { sudo -n "$@"; }

unit_active() { systemctl is-active --quiet "$1"; }

ensure_dirs() {
  install -d -m 700 "$STATE_DIR" "$TOKENS_DIR"
}

# Wait for cloudflared to publish the public hostname it just negotiated.
tunnel_url() {
  local deadline=$(( SECONDS + ${1:-45} ))
  local url=""
  while (( SECONDS < deadline )); do
    if [[ -f "$TUNNEL_LOG" ]]; then
      url="$(grep -oE "$URL_RE" "$TUNNEL_LOG" 2>/dev/null | tail -1)"
      [[ -n "$url" ]] && { printf '%s\n' "$url"; return 0; }
    fi
    sleep 1
  done
  return 1
}

cmd_on() {
  # Only refuse while the one-time setup wizard is still live: that flow owns
  # the box's attention (and its own web terminal) until it completes. A box
  # that never ran the wizard at all — a dev box built with setup-vps.sh — is
  # perfectly entitled to a board.
  if systemctl is-active --quiet setup-web.service 2>/dev/null; then
    fail "Finish setting up this box first, then ask me for the board again."
  fi
  command -v cloudflared >/dev/null \
    || fail "cloudflared is missing — run kappmaker-board-install to repair the board."

  ensure_dirs
  if ! unit_active "$BOARD_UNIT"; then
    sudo_n systemctl enable --now "$BOARD_UNIT" >/dev/null 2>&1 \
      || fail "Could not start the board service."
  fi
  if ! unit_active "$TUNNEL_UNIT"; then
    sudo_n systemctl enable --now "$TUNNEL_UNIT" >/dev/null 2>&1 \
      || fail "Could not start the board tunnel."
  fi
  # Starting the board counts as activity. Without this the idle timer below
  # fires immediately (systemd runs a Persistent= timer whose interval already
  # elapsed at boot), sees no last-seen, and shuts the board straight back down.
  date -u +%s > "$STATE_DIR/last-seen"

  # So a board left on after a quick look does not stay exposed for weeks.
  sudo_n systemctl enable --now kappmaker-board-idle.timer >/dev/null 2>&1 || true

  local url
  url="$(tunnel_url 45)" || fail "The tunnel did not come up in time. Try again in a minute."
  printf '%s\n' "$url"
}

cmd_off() {
  sudo_n systemctl disable --now kappmaker-board-idle.timer >/dev/null 2>&1 || true
  sudo_n systemctl disable --now "$TUNNEL_UNIT" >/dev/null 2>&1 || true
  sudo_n systemctl disable --now "$BOARD_UNIT"  >/dev/null 2>&1 || true
  rm -f "$TUNNEL_LOG" "$STATE_DIR/last-seen"
  rm -rf "$TOKENS_DIR"
  say "${GREEN}Board is off.${RESET} It is not reachable from anywhere until you ask for it again."
}

cmd_link() {
  local url
  if unit_active "$TUNNEL_UNIT" && url="$(tunnel_url 5)"; then
    :
  else
    url="$(cmd_on)" || exit 1
  fi

  ensure_dirs
  local token hash
  token="$(openssl rand -hex 32)" || fail "Could not generate a login token."
  # The server looks the token up by its SHA-256, so the secret itself is never
  # written to disk — only its hash, as an empty file whose mtime is the clock.
  hash="$(printf '%s' "$token" | sha256sum | cut -d' ' -f1)"
  : > "$TOKENS_DIR/$hash"
  chmod 600 "$TOKENS_DIR/$hash"

  # Sweep spent/expired tokens so the directory cannot grow without bound.
  find "$TOKENS_DIR" -type f -mmin +15 -delete 2>/dev/null || true

  say "${BOLD}Your project board:${RESET}"
  say "$url/login?t=$token"
  say ""
  say "${DIM}This link signs you in once and then stops working (10 minutes to use it).${RESET}"
  say "${DIM}Ask me again any time for a fresh one.${RESET}"
}

cmd_status() {
  local board="off" tunnel="off" url="-" seen="never"
  unit_active "$BOARD_UNIT"  && board="running"
  unit_active "$TUNNEL_UNIT" && tunnel="running"
  [[ -f "$TUNNEL_LOG" ]] && url="$(grep -oE "$URL_RE" "$TUNNEL_LOG" 2>/dev/null | tail -1)"
  if [[ -f "$STATE_DIR/last-seen" ]]; then
    seen="$(date -u -d "@$(cat "$STATE_DIR/last-seen")" '+%Y-%m-%d %H:%M UTC' 2>/dev/null || echo unknown)"
  fi
  say "board:   $board"
  say "tunnel:  $tunnel"
  say "address: ${url:--}"
  say "last viewed: $seen"
  say "sessions: $( [[ -f "$STATE_DIR/sessions.json" ]] && grep -o '{' "$STATE_DIR/sessions.json" | wc -l | tr -d ' ' || echo 0 )"
}

cmd_logout_all() {
  rm -f "$STATE_DIR/sessions.json"
  rm -rf "$TOKENS_DIR"
  unit_active "$BOARD_UNIT" && sudo_n systemctl restart "$BOARD_UNIT" >/dev/null 2>&1
  say "${GREEN}Signed out everywhere.${RESET} Ask me for a new board link when you want back in."
}

# Called by kappmaker-board-idle.timer: if nobody has looked at the board for
# IDLE_HOURS, take it back off the internet. `link` brings it straight back.
cmd_idle_check() {
  unit_active "$TUNNEL_UNIT" || exit 0
  # No last-seen means we have no evidence either way — never shut a board down
  # on a guess. `on` always stamps this file, so absence is a broken state, not
  # an idle one.
  [[ -f "$STATE_DIR/last-seen" ]] || exit 0
  local last
  last="$(cat "$STATE_DIR/last-seen" 2>/dev/null || echo 0)"
  [[ "$last" =~ ^[0-9]+$ ]] || exit 0
  local cutoff=$(( $(date -u +%s) - IDLE_HOURS * 3600 ))
  if (( last < cutoff )); then
    cmd_off >/dev/null
    say "board stopped after ${IDLE_HOURS}h idle"
  fi
}

case "${1:-}" in
  on)         cmd_on ;;
  off)        cmd_off ;;
  link)       cmd_link ;;
  status)     cmd_status ;;
  logout-all) cmd_logout_all ;;
  idle-check) cmd_idle_check ;;
  *)          usage ;;
esac
