#!/usr/bin/env bash
# KAppMaker AI — non-interactive box bootstrap (cloud-init entry point).
#
# Runs as root on first boot of a fresh Ubuntu/Debian VPS. It:
#   1. creates a non-root sudo user (devuser),
#   2. installs the full toolchain via setup-vps.sh (non-interactive, no loop),
#   3. applies the security baseline (UFW, SSH lockdown, fail2ban, auto-upgrades),
#   4. installs the always-on Claude+Telegram systemd service,
#   5. installs the one-time BROWSER SETUP terminal (ttyd behind Caddy TLS) so a
#      non-technical customer can finish setup with no SSH and no keys,
#   6. pings the control-plane callback that the box is up + awaiting customer
#      setup, including the browser-setup URL + access code.
#
# ZERO-KNOWLEDGE: no customer secret is passed in here. The customer logs into
# Claude and pastes their Telegram token directly on the box (via the browser
# wizard or SSH); those credentials never leave the box. The only extra data
# sent to the control plane is setup_url + setup_code, which merely GATE access
# to the setup wizard — they are not stored customer secrets.
#
# Tunables (all optional, passed as env by cloud-init user-data):
#   DEVUSER             non-root user to create           (default: devuser)
#   SETUP_VPS_URL       URL of setup-vps.sh to run         (default: GitHub raw main)
#   PROVISION_BASE_URL  base URL for the provision/ files  (default: GitHub raw main)
#   SERVER_CALLBACK_URL signed control-plane callback URL  (optional)
#   SERVER_KEY_URL      signed URL returning the customer's current PUBLIC
#                       ssh key — polled by the runner so a key added in the
#                       dashboard works without a rebuild (optional)
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
SERVER_KEY_URL="${SERVER_KEY_URL:-}"
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

# progress <percent> <step>: update the build phase shown to the customer.
# Non-fatal, non-blocking — never let a progress ping stall the build.
progress() {
  local percent="$1" step="$2"
  log "$step ($percent%)"
  [[ -n "$SERVER_CALLBACK_URL" ]] || return 0
  curl -fsS --max-time 8 -X POST "$SERVER_CALLBACK_URL" \
    --data-urlencode "state=progress" \
    --data-urlencode "percent=$percent" \
    --data-urlencode "step=$step" \
    >/dev/null 2>&1 || true
}

trap 'callback error "bootstrap failed (see /var/log/kappmaker-bootstrap.log)"' ERR

# ---------- 1. base packages ----------
progress 10 "Starting up your machine"
apt-get update -y
apt-get install -y curl wget git sudo ufw fail2ban unattended-upgrades

# ---------- 2. non-root sudo user ----------
log "Creating non-root user: $DEVUSER"
# Hetzner images created without ssh_keys ship an EXPIRED root password, which
# makes PAM fail adduser's chfn step ("authentication token is no longer
# valid"). Unexpire root and use useradd (no chfn involved) — both harmless
# when the image is healthy.
chage -d "$(date +%Y-%m-%d)" -M -1 root 2>/dev/null || true
if ! id "$DEVUSER" >/dev/null 2>&1; then
  useradd -m -s /bin/bash "$DEVUSER"
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
progress 30 "Installing the app-building tools (this is the long part)"
TMP_SETUP="$(mktemp --suffix=.sh)"
curl -fsSL "$SETUP_VPS_URL" -o "$TMP_SETUP"
chmod 755 "$TMP_SETUP"  # a+rx: mktemp gives 0600 root — devuser must be able to read it
sudo -u "$DEVUSER" -H env KAPP_NONINTERACTIVE=1 KAPP_SKIP_LOOP=1 bash "$TMP_SETUP"
rm -f "$TMP_SETUP"

progress 70 "Locking your machine down (security)"
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
progress 85 "Setting up your always-on assistant"
install -d -o "$DEVUSER" -g "$DEVUSER" "/home/$DEVUSER/bin"

# Persist the (secret-free, signed) callback URL so the runner can report
# "setup_complete" to the control plane once the customer finishes setup.
if [[ -n "$SERVER_CALLBACK_URL" || -n "${SERVER_KEY_URL:-}" ]]; then
  install -d -o "$DEVUSER" -g "$DEVUSER" "/home/$DEVUSER/.config/kappmaker"
  KAPP_ENV_FILE="/home/$DEVUSER/.config/kappmaker/env"
  # MERGE, never truncate: setup-vps.sh stores the toolchain env (JAVA_HOME,
  # ANDROID_SDK_ROOT, PATH…) in this same file — clobbering it would strip the
  # build tools from claude-telegram.service's environment.
  touch "$KAPP_ENV_FILE"
  sed -i '/^SERVER_CALLBACK_URL=/d; /^SERVER_KEY_URL=/d' "$KAPP_ENV_FILE"
  {
    [[ -n "$SERVER_CALLBACK_URL" ]] && printf 'SERVER_CALLBACK_URL=%q\n' "$SERVER_CALLBACK_URL"
    [[ -n "${SERVER_KEY_URL:-}" ]] && printf 'SERVER_KEY_URL=%q\n' "${SERVER_KEY_URL:-}"
  } >> "$KAPP_ENV_FILE"
  chown "$DEVUSER:$DEVUSER" "$KAPP_ENV_FILE"
  chmod 600 "$KAPP_ENV_FILE"
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

# ---------- 5b. one-time browser setup (ttyd wizard behind Caddy TLS) ----------
# Non-technical customers finish setup FROM THE BROWSER — no SSH, no keys:
# ttyd (loopback-only) serves setup-wizard.sh in a web terminal; Caddy fronts
# it with REAL TLS on an sslip.io hostname (the box IP with dashes, e.g.
# 203-0-113-7.sslip.io). Access is gated by basic auth: user "setup" + a random
# code generated here and shown to the customer in the dashboard.
#
# TLS choice: Caddy auto-issues via Let's Encrypt first. sslip.io's LE quota is
# shared by every sslip.io user on the internet and has been exhausted before
# (github.com/cunnie/sslip.io/issues/108 — LE raised it to 250k/week), so
# Caddy's built-in ZeroSSL fallback is the safety net; if issuance still fails
# Caddy keeps retrying with backoff and the customer can use the SSH path.
# This beats plain HTTP on a high port: the setup code and the Telegram token
# the customer types must not cross the wire in cleartext.
#
# ZERO-KNOWLEDGE: setup_url + setup_code only GATE access to the wizard while
# setup is incomplete; they are not customer secrets and gate nothing once
# setup-teardown.sh runs. Claude credentials + Telegram token are entered on
# the box and never leave it.
#
# Torn down by /usr/local/bin/kappmaker-setup-teardown (invoked by the runner
# on first successful start), which also writes /etc/kappmaker/.setup-done —
# making this whole section a no-op on any later bootstrap re-run.
SETUP_URL=""
SETUP_CODE=""
if [[ -f /etc/kappmaker/.setup-done ]]; then
  log "Customer setup already complete — skipping browser-setup terminal"
elif ! apt-get install -y ttyd caddy openssl; then
  warn "ttyd/caddy not installable — browser setup skipped (SSH path still works)"
else
  log "Installing one-time browser-setup terminal (ttyd + Caddy)"

  # Random access code = the basic-auth password (user is always "setup").
  # Reused across re-runs so a URL/code already shown to the customer stays valid.
  install -d -m 755 /etc/kappmaker
  if [[ ! -f /etc/kappmaker/setup-web.env ]]; then
    SETUP_CODE="$(openssl rand -hex 16)"   # 32 chars, [0-9a-f]
    printf 'SETUP_CODE=%s\n' "$SETUP_CODE" > /etc/kappmaker/setup-web.env
    chmod 600 /etc/kappmaker/setup-web.env
  else
    SETUP_CODE="$(sed -n 's/^SETUP_CODE=//p' /etc/kappmaker/setup-web.env)"
  fi

  curl -fsSL "$PROVISION_BASE_URL/setup-wizard.sh" -o "/home/$DEVUSER/bin/setup-wizard.sh"
  chown "$DEVUSER:$DEVUSER" "/home/$DEVUSER/bin/setup-wizard.sh"
  chmod +x "/home/$DEVUSER/bin/setup-wizard.sh"

  curl -fsSL "$PROVISION_BASE_URL/setup-teardown.sh" -o /usr/local/bin/kappmaker-setup-teardown
  chmod 755 /usr/local/bin/kappmaker-setup-teardown

  TMP_UNIT="$(mktemp)"
  curl -fsSL "$PROVISION_BASE_URL/setup-web.service" -o "$TMP_UNIT"
  sed "s/__DEVUSER__/$DEVUSER/g" "$TMP_UNIT" > /etc/systemd/system/setup-web.service
  rm -f "$TMP_UNIT"

  # Public IPv4 → sslip.io hostname. Hetzner metadata first, generic fallback.
  SETUP_IP="$(curl -fsS --max-time 5 http://169.254.169.254/hetzner/v1/metadata/public-ipv4 2>/dev/null || true)"
  [[ "$SETUP_IP" =~ ^[0-9]+(\.[0-9]+){3}$ ]] \
    || SETUP_IP="$(curl -4fsS --max-time 10 https://api.ipify.org 2>/dev/null || true)"

  if [[ "$SETUP_IP" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    SETUP_HOST="${SETUP_IP//./-}.sslip.io"

    cat > /etc/caddy/Caddyfile <<CADDY
# KAppMaker AI — one-time browser setup (written by bootstrap.sh, removed with
# the setup flow by kappmaker-setup-teardown). Caddy auto-issues a certificate
# for the sslip.io name (Let's Encrypt, ZeroSSL fallback) and proxies to the
# loopback-only ttyd; basic auth is enforced by ttyd itself.
$SETUP_HOST {
	reverse_proxy 127.0.0.1:7681
}
CADDY

    # Setup-only ports — closed again by kappmaker-setup-teardown.
    ufw allow 80/tcp  comment 'kappmaker browser setup (ACME + redirect)'
    ufw allow 443/tcp comment 'kappmaker browser setup (wizard)'

    systemctl daemon-reload
    systemctl enable --now setup-web.service
    systemctl enable caddy.service >/dev/null 2>&1 || true
    systemctl restart caddy.service

    SETUP_URL="https://$SETUP_HOST/"
    log "Browser setup live at $SETUP_URL (user: setup)"
  else
    warn "Could not determine public IPv4 — browser setup skipped (SSH path still works)"
    SETUP_CODE=""
  fi
fi

progress 97 "Almost ready"
# ---------- 6. notify control plane ----------
log "Bootstrap complete — box is up and awaiting customer setup"
callback awaiting_setup "bootstrap complete"

# Publish the browser-setup coordinates so the dashboard can show the customer
# a "Finish setup" button. Contract: state=awaiting_setup + setup_url +
# setup_code (basic-auth user is always "setup"). These gate setup access only
# — no customer secret is ever sent (see ZERO-KNOWLEDGE note above).
if [[ -n "$SERVER_CALLBACK_URL" && -n "$SETUP_URL" && -n "$SETUP_CODE" ]]; then
  curl -fsS -X POST "$SERVER_CALLBACK_URL" \
    --data-urlencode "state=awaiting_setup" \
    --data-urlencode "setup_url=$SETUP_URL" \
    --data-urlencode "setup_code=$SETUP_CODE" \
    >/dev/null 2>&1 || warn "setup_url callback failed — dashboard won't show the browser-setup link"
fi
trap - ERR

SETUP_URL_DISPLAY="${SETUP_URL:-(browser setup unavailable — see warnings above)}"
cat <<NEXT

────────────────────────────────────────────────────────────
Box is provisioned + hardened. The customer finishes setup IN THE BROWSER:
  $SETUP_URL_DISPLAY
  login: user "setup" + the setup code (shown in the KAppMaker dashboard)
The wizard walks them through Claude login + Telegram bot token, then the
setup page shuts itself down automatically.

SSH fallback (if the browser path is unavailable), on the box as $DEVUSER:
  1. claude            # log into your Claude subscription
  2. /telegram:configure <BotFather token>
  3. /telegram:access pair <code>   (DM your bot to get the code)
The always-on service starts automatically once setup is done.
────────────────────────────────────────────────────────────
NEXT
