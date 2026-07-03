#!/usr/bin/env bash
# KAppMaker AI — non-interactive box bootstrap (cloud-init entry point).
#
# Runs as root on first boot of a fresh Ubuntu/Debian VPS. It:
#   1. creates a non-root sudo user (devuser),
#   2. installs the full toolchain via setup-vps.sh (non-interactive, no loop),
#   3. applies the security baseline (UFW, SSH lockdown, fail2ban, auto-upgrades),
#   4. installs the always-on Claude+Telegram systemd service,
#   5. pings the control-plane callback that the box is up + awaiting customer setup.
#
# ZERO-KNOWLEDGE: no customer secret is passed in here. The customer logs into
# Claude and pastes their Telegram token directly on the box afterwards.
#
# Tunables (all optional, passed as env by cloud-init user-data):
#   DEVUSER             non-root user to create           (default: devuser)
#   SETUP_VPS_URL       URL of setup-vps.sh to run         (default: GitHub raw main)
#   PROVISION_BASE_URL  base URL for the provision/ files  (default: GitHub raw main)
#   SERVER_CALLBACK_URL signed control-plane callback URL  (optional)
#   CUSTOMER_SSH_KEY    customer's PUBLIC ssh key — installed for DEVUSER so the
#                       customer can log in for the one-time setup (optional)

set -euo pipefail

log()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[err]\033[0m  %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || die "bootstrap.sh must run as root (cloud-init does this)."
command -v apt-get >/dev/null || die "Debian/Ubuntu only (apt-get not found)."

DEVUSER="${DEVUSER:-devuser}"
RAW_BASE="https://raw.githubusercontent.com/KAppMaker/KAppMakerDeveloperBot/main"
SETUP_VPS_URL="${SETUP_VPS_URL:-$RAW_BASE/setup-vps.sh}"
PROVISION_BASE_URL="${PROVISION_BASE_URL:-$RAW_BASE/provision}"
SERVER_CALLBACK_URL="${SERVER_CALLBACK_URL:-}"
CUSTOMER_SSH_KEY="${CUSTOMER_SSH_KEY:-}"

export DEBIAN_FRONTEND=noninteractive

callback() {
  # state: awaiting_setup | error  (no secrets, just lifecycle signal)
  local state="$1" message="${2:-}"
  [[ -n "$SERVER_CALLBACK_URL" ]] || return 0
  curl -fsS -X POST "$SERVER_CALLBACK_URL" \
    --data-urlencode "state=$state" \
    --data-urlencode "message=$message" \
    >/dev/null 2>&1 || warn "callback ($state) failed — control plane not notified"
}

trap 'callback error "bootstrap failed (see /var/log/kappmaker-bootstrap.log)"' ERR

# ---------- 1. base packages ----------
log "Installing base packages"
apt-get update -y
apt-get install -y curl wget git sudo ufw fail2ban unattended-upgrades

# ---------- 2. non-root sudo user ----------
log "Creating non-root user: $DEVUSER"
if ! id "$DEVUSER" >/dev/null 2>&1; then
  adduser --disabled-password --gecos "" "$DEVUSER"
fi
usermod -aG sudo "$DEVUSER"
# Passwordless sudo: required for hands-off --dangerously-skip-permissions operation.
# Acceptable only because the box is locked to the owner (hardening below).
echo "$DEVUSER ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$DEVUSER"
chmod 440 "/etc/sudoers.d/$DEVUSER"
visudo -c >/dev/null

# Customer's PUBLIC ssh key → devuser login (their door into their own box).
if [[ -n "$CUSTOMER_SSH_KEY" ]]; then
  install -d -m 700 -o "$DEVUSER" -g "$DEVUSER" "/home/$DEVUSER/.ssh"
  if ! grep -qsF "$CUSTOMER_SSH_KEY" "/home/$DEVUSER/.ssh/authorized_keys" 2>/dev/null; then
    echo "$CUSTOMER_SSH_KEY" >> "/home/$DEVUSER/.ssh/authorized_keys"
  fi
  chown "$DEVUSER:$DEVUSER" "/home/$DEVUSER/.ssh/authorized_keys"
  chmod 600 "/home/$DEVUSER/.ssh/authorized_keys"
fi

# ---------- 3. toolchain (non-interactive, no loop) ----------
log "Installing toolchain via setup-vps.sh as $DEVUSER (non-interactive)"
TMP_SETUP="$(mktemp --suffix=.sh)"
curl -fsSL "$SETUP_VPS_URL" -o "$TMP_SETUP"
chmod +x "$TMP_SETUP"
sudo -u "$DEVUSER" -H env KAPP_NONINTERACTIVE=1 KAPP_SKIP_LOOP=1 bash "$TMP_SETUP"
rm -f "$TMP_SETUP"

# ---------- 4. security baseline ----------
# (mirrors README "Securing the VPS"). NOTE: SSH stays reachable on :22 here so the
# operator/customer can still get in. Tighten to Tailscale-only as a follow-up once
# Tailscale is joined — see README. Locking SSH before Tailscale would risk lockout.
log "Applying security baseline (UFW, SSH lockdown, fail2ban, auto-upgrades)"

ufw --force default deny incoming
ufw --force default allow outgoing
ufw allow OpenSSH
# Outbound mail blocked: boxes never send mail, and this makes spam/open-relay
# abuse (Hetzner ToS §5.2/§8.3) impossible by construction.
ufw deny out 25/tcp
ufw deny out 465/tcp
ufw deny out 587/tcp
ufw --force enable

# SSH: key-only, no root login.
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin no/'             /etc/ssh/sshd_config
sshd -t && systemctl restart ssh

systemctl enable --now fail2ban
dpkg-reconfigure -f noninteractive unattended-upgrades || true

# ---------- 5. always-on Claude + Telegram service ----------
log "Installing always-on Claude+Telegram systemd service"
install -d -o "$DEVUSER" -g "$DEVUSER" "/home/$DEVUSER/bin"

# Persist the (secret-free, signed) callback URL so the runner can report
# "setup_complete" to the control plane once the customer finishes setup.
if [[ -n "$SERVER_CALLBACK_URL" ]]; then
  install -d -o "$DEVUSER" -g "$DEVUSER" "/home/$DEVUSER/.config/kappmaker"
  printf 'SERVER_CALLBACK_URL=%q\n' "$SERVER_CALLBACK_URL" > "/home/$DEVUSER/.config/kappmaker/env"
  chown "$DEVUSER:$DEVUSER" "/home/$DEVUSER/.config/kappmaker/env"
  chmod 600 "/home/$DEVUSER/.config/kappmaker/env"
fi
curl -fsSL "$PROVISION_BASE_URL/claude-telegram-run.sh" -o "/home/$DEVUSER/bin/claude-telegram-run.sh"
chown "$DEVUSER:$DEVUSER" "/home/$DEVUSER/bin/claude-telegram-run.sh"
chmod +x "/home/$DEVUSER/bin/claude-telegram-run.sh"

TMP_UNIT="$(mktemp)"
curl -fsSL "$PROVISION_BASE_URL/claude-telegram.service" -o "$TMP_UNIT"
sed "s/__DEVUSER__/$DEVUSER/g" "$TMP_UNIT" > /etc/systemd/system/claude-telegram.service
rm -f "$TMP_UNIT"

systemctl daemon-reload
# Enable + start: it will harmlessly wait-and-restart until the customer finishes setup.
systemctl enable --now claude-telegram.service

# ---------- 6. notify control plane ----------
log "Bootstrap complete — box is up and awaiting customer setup"
callback awaiting_setup "bootstrap complete"
trap - ERR

cat <<NEXT

────────────────────────────────────────────────────────────
Box is provisioned + hardened. Finish setup ON THE BOX (as $DEVUSER):
  1. claude            # log into your Claude subscription
  2. /telegram:configure <BotFather token>
  3. /telegram:access pair <code>   (DM your bot to get the code)
The always-on service starts automatically once both are done.
────────────────────────────────────────────────────────────
NEXT
