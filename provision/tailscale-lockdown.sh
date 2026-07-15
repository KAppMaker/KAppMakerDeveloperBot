#!/usr/bin/env bash
# kappmaker-tailscale-lockdown — OPTIONAL extra hardening, run by the box OWNER.
#
# Locks SSH to their private Tailscale network so the public internet can no
# longer even knock on port 22. Guided + fail-safe:
#   1. installs Tailscale if missing,
#   2. joins the OWNER's tailnet (`tailscale up` prints a login link — their
#      account, their network; zero-knowledge: we never see it),
#   3. refuses to touch the firewall until the owner confirms they have TESTED
#      an SSH login over the Tailscale IP from a second terminal,
#   4. then allows SSH on the tailscale0 interface and removes the public rule.
#
# Recovery if it ever goes wrong: the dashboard "Rebuild" gives a fresh box
# (apps should live on GitHub; Claude/Telegram are re-entered in setup).
#
# Installed to /usr/local/bin/kappmaker-tailscale-lockdown by bootstrap.sh.
set -euo pipefail

BOLD=$'\e[1m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RED=$'\e[31m'; RESET=$'\e[0m'
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓ %s%s\n' "$GREEN" "$*" "$RESET"; }
warn() { printf '%s! %s%s\n' "$YELLOW" "$*" "$RESET"; }
die()  { printf '%s✗ %s%s\n' "$RED" "$*" "$RESET"; exit 1; }

[[ $EUID -eq 0 ]] || die "Run with sudo: sudo kappmaker-tailscale-lockdown"

say ""
say "${BOLD}Lock SSH to your private Tailscale network${RESET}"
say "After this, port 22 disappears from the public internet — only devices"
say "on YOUR tailnet can reach the box. (Telegram/Claude are unaffected: the"
say "box only makes outbound connections for those.)"
say ""

# ---------- 1. install ----------
if ! command -v tailscale >/dev/null 2>&1; then
  say "Installing Tailscale…"
  curl -fsSL https://tailscale.com/install.sh | sh || die "Tailscale install failed."
fi
ok "Tailscale installed"

# ---------- 2. join the owner's tailnet ----------
if ! tailscale status >/dev/null 2>&1; then
  say ""
  say "Joining your tailnet — a login link will appear below. Open it in your"
  say "browser and sign in with YOUR Tailscale account (free for personal use)."
  say ""
  tailscale up || die "tailscale up failed — nothing was changed."
fi

TS_IP="$(tailscale ip -4 2>/dev/null | head -1 || true)"
[[ -n "$TS_IP" ]] || die "No Tailscale IP yet — is the tailnet joined? Nothing was changed."
ok "This box is on your tailnet as: $TS_IP"

# ---------- 3. the fail-safe gate ----------
say ""
warn "BEFORE the firewall changes, prove the new door works:"
say "  1. Install Tailscale on your laptop + sign into the SAME account."
say "  2. In a ${BOLD}second terminal${RESET}, connect over the tailnet:"
say "       ssh -i ~/.ssh/kappmaker_key devuser@$TS_IP"
say "  3. Keep THIS session open the whole time."
say ""
printf '%s' "Did the Tailscale SSH login in the second terminal WORK? Type ${BOLD}yes${RESET} to lock down (anything else aborts): "
read -r answer
[[ "$answer" == "yes" ]] || { say "Aborted — firewall untouched. Run again any time."; exit 0; }

# ---------- 4. swap the firewall rules ----------
ufw allow in on tailscale0 to any port 22 proto tcp comment 'SSH via Tailscale only' >/dev/null
ufw delete allow OpenSSH >/dev/null 2>&1 || true
ufw delete allow 22/tcp  >/dev/null 2>&1 || true
ok "SSH is now Tailscale-only"

say ""
say "${BOLD}Done.${RESET} From now on connect with:"
say "    ssh -i ~/.ssh/kappmaker_key devuser@$TS_IP"
say ""
say "Undo any time (reopens public SSH):"
say "    sudo ufw allow OpenSSH && sudo ufw delete allow in on tailscale0 to any port 22 proto tcp"
