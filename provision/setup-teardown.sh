#!/usr/bin/env bash
# KAppMaker AI — tear down the one-time browser-setup flow.
#
# Installed by bootstrap.sh as /usr/local/bin/kappmaker-setup-teardown and
# invoked (via passwordless sudo) by claude-telegram-run.sh the first time it
# starts with the customer's credentials in place — i.e. the moment setup is
# actually complete.
#
# It closes the box back down to its steady state:
#   - stop + disable setup-web.service (ttyd) and caddy.service,
#   - close the temporary UFW ports (80 = ACME/redirect, 443 = setup page),
#   - delete the spent SETUP_CODE,
#   - write /etc/kappmaker/.setup-done so neither a bootstrap re-run nor the
#     unit's ConditionPathExists ever brings the setup terminal back.
#
# Idempotent: safe to run any number of times, on boxes with or without the
# browser-setup flow installed.

set -uo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "kappmaker-setup-teardown: must run as root (use sudo)." >&2
  exit 1
fi

# Marker first: even if a step below hiccups, nothing will re-open setup access.
install -d -m 755 /etc/kappmaker
touch /etc/kappmaker/.setup-done

systemctl disable --now setup-web.service >/dev/null 2>&1 || true
systemctl disable --now caddy.service     >/dev/null 2>&1 || true

# Close the setup-only firewall ports (opened by bootstrap.sh).
ufw delete allow 80/tcp  >/dev/null 2>&1 || true
ufw delete allow 443/tcp >/dev/null 2>&1 || true

# The setup code is spent — remove it.
rm -f /etc/kappmaker/setup-web.env

echo "kappmaker-setup-teardown: browser-setup terminal disabled, ports 80/443 closed."
