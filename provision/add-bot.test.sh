#!/bin/sh
# Tests for provision/add-bot.sh — the two steps a new helper needs before its
# systemd unit starts. Both failures look identical from Telegram: the bot just
# never answers.
#
#   1. The boot folder must exist before `systemctl enable --now`: the unit's
#      WorkingDirectory is entered BEFORE the worker script runs, so a missing
#      folder means a restart loop every 15 s forever.
#   2. Folder trust must be pre-accepted for that folder, or the first launch
#      stops at "do you trust this folder?" with "No, exit" preselected.
#
# Run: sh provision/add-bot.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/provision/add-bot.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

pass=0; fail=0
ok()   { pass=$((pass+1)); printf 'ok   - %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf 'FAIL - %s\n' "$1"; }
check(){ if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }

line_of() { grep -n "$1" "$SRC" | head -n1 | cut -d: -f1; }

enable_at="$(line_of 'systemctl enable --now')"
mkdir_at="$(line_of 'install -d -m 755 "$BOOT_DIR"')"
trust_at="$(line_of 'hasTrustDialogAccepted')"

[ -n "$enable_at" ]; check $? "add-bot enables the unit"
[ -n "$mkdir_at" ] && [ "$mkdir_at" -lt "$enable_at" ]; check $? "boot folder is created BEFORE the unit starts"
[ -n "$trust_at" ] && [ "$trust_at" -lt "$enable_at" ]; check $? "folder trust is seeded BEFORE the unit starts"
grep -q 'BOOT_DIR="$HOME/workspaces/$INSTANCE"' "$SRC"; check $? "boot folder matches the unit's WorkingDirectory (~/workspaces/<instance>)"

# Run the embedded trust merge for real, against a ~/.claude.json that other
# helpers have already written to.
sed -n '/^python3 - "\$BOOT_DIR" <<'"'"'PY'"'"'/,/^PY$/p' "$SRC" | sed '1d;$d' > "$T/merge.py"
[ -s "$T/merge.py" ]; check $? "trust merge snippet extracted"

printf '%s\n' '{"theme":"dark","projects":{"/home/u/projects":{"hasTrustDialogAccepted":true,"mcpServers":{"x":{}}}},"mcpServers":{"stitch":{}}}' > "$T/.claude.json"
chmod 600 "$T/.claude.json"
HOME="$T" python3 "$T/merge.py" "/home/u/workspaces/app3"; check $? "trust merge runs"

python3 - "$T/.claude.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
p = d["projects"]
assert p["/home/u/workspaces/app3"]["hasTrustDialogAccepted"] is True, "new folder not trusted"
assert p["/home/u/projects"]["hasTrustDialogAccepted"] is True, "existing trust lost"
assert "x" in p["/home/u/projects"]["mcpServers"], "existing project config lost"
assert d["theme"] == "dark" and "stitch" in d["mcpServers"], "top-level keys lost"
PY
check $? "merge adds the new folder and keeps everything the live helpers wrote"

mode="$(stat -c %a "$T/.claude.json" 2>/dev/null || stat -f %Lp "$T/.claude.json")"
[ "$mode" = "600" ]; check $? "file permissions preserved (600)"

# Idempotent: running it twice changes nothing more.
cp "$T/.claude.json" "$T/before.json"
HOME="$T" python3 "$T/merge.py" "/home/u/workspaces/app3"
python3 -c "import json,sys; sys.exit(0 if json.load(open('$T/before.json'))==json.load(open('$T/.claude.json')) else 1)"
check $? "re-running is a no-op"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
