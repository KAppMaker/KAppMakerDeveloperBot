#!/usr/bin/env bash
# KAppMaker AI — browser-setup auto-expiry (run by setup-expiry.timer, 48h after boot).
#
# Safety net: if the customer never finishes setup, the one-time browser terminal
# would otherwise stay up (code-gated) forever. This tears it down after the
# window closes and tells the control plane so the dashboard stops offering a
# dead "Open setup page" button. If setup was already completed, this is a no-op
# (the runner writes .setup-complete-sent once it reports setup_complete).
#
# Runs as root (systemd). Reads the signed, secret-free callback URL from the
# box owner's kappmaker env.

set -uo pipefail

DEVUSER="${DEVUSER:-devuser}"
KAPP_ENV="/home/$DEVUSER/.config/kappmaker/env"
COMPLETE_MARKER="/home/$DEVUSER/.config/kappmaker/.setup-complete-sent"

# Setup already finished → nothing to expire.
[[ -f "$COMPLETE_MARKER" ]] && exit 0

# Already torn down (e.g. completed via SSH) → nothing to do.
[[ -f /etc/kappmaker/.setup-done ]] && exit 0

# Close the setup surface (idempotent).
if [[ -x /usr/local/bin/kappmaker-setup-teardown ]]; then
  /usr/local/bin/kappmaker-setup-teardown || true
fi

# Tell the control plane the browser-setup window expired so it can clear the
# stale link. Carries only a lifecycle signal — no secret.
SERVER_CALLBACK_URL=""
# shellcheck disable=SC1090
[[ -f "$KAPP_ENV" ]] && source "$KAPP_ENV"

if [[ -n "${SERVER_CALLBACK_URL:-}" ]]; then
  curl -fsS --max-time 10 -X POST "$SERVER_CALLBACK_URL" \
    --data-urlencode "state=setup_expired" \
    --data-urlencode "message=browser setup window expired" \
    >/dev/null 2>&1 || true
fi
