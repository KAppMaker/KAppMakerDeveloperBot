#!/bin/sh
# loop-guard.test.sh — behaviour tests for templates/loop/scripts/loop-guard.sh
#
# Run: sh provision/loop-guard.test.sh
#
# The guard is a Stop hook, so its whole contract is "what does it print, and does the
# loop keep running". The cases that matter are the ones that used to be silent: a run
# that hit its cap, a red build, and a run that actually finished all looked identical
# from the owner's phone. Each of those must now announce exactly once and then stop
# for real — announcing forever would be an infinite loop, announcing never is the bug
# these tests exist to catch.

set -u

GUARD="$(cd "$(dirname "$0")/.." && pwd)/templates/loop/scripts/loop-guard.sh"
[ -f "$GUARD" ] || { echo "loop-guard.sh not found at $GUARD"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 1
mkdir -p .claude

export CLAUDE_PROJECT_DIR="$WORK"
export KAPP_LOOP_FAKE_VERIFY=pass

FAILED=0
chk() {
  if [ "$2" = "$3" ]; then
    echo "  ok   $1"
  else
    echo "  FAIL $1: got [$2] want [$3]"
    FAILED=1
  fi
}
run() { echo "${1:-\{\}}" | sh "$GUARD" 2>/dev/null; }
blocked() { case "$1" in *'"decision":"block"'*) echo yes ;; *) echo no ;; esac; }
exists() { [ -f "$1" ] && echo yes || echo no; }

reset() { rm -f .claude/.loop-active .claude/.loop-count .claude/.loop-announced; }

echo "loop-guard:"

# The loop is off by default: a normal session must stop normally.
reset
chk "loop off is silent" "$(run)" ""

# Mandatory infinite-loop guard.
reset; : > .claude/.loop-active
chk "stop_hook_active is inert" "$(run '{"stop_hook_active":true}')" ""

# Work remains -> keep going, and the announce latch must be cleared so a later
# stop can still announce.
reset; : > .claude/.loop-active
printf -- "- [ ] something left\n" > PLAN.md
chk "unchecked items continue the loop" "$(blocked "$(run)")" "yes"
chk "continuing clears the announce latch" "$(exists .claude/.loop-announced)" "no"

# Finished run: announce once, then stop and clear the flag.
reset; : > .claude/.loop-active
printf -- "- [x] all done\n" > PLAN.md
chk "complete announces" "$(blocked "$(run)")" "yes"
chk "complete keeps the flag while announcing" "$(exists .claude/.loop-active)" "yes"
chk "complete is silent on the second pass" "$(run)" ""
chk "complete clears the flag" "$(exists .claude/.loop-active)" "no"
chk "complete clears the latch" "$(exists .claude/.loop-announced)" "no"

# Iteration cap: announce, then stop.
reset; : > .claude/.loop-active; echo 99 > .claude/.loop-count
OUT="$(run)"
chk "cap announces" "$(blocked "$OUT")" "yes"
case "$OUT" in *"iteration cap"*) chk "cap says why" yes yes ;; *) chk "cap says why" no yes ;; esac
run >/dev/null
chk "cap clears the flag" "$(exists .claude/.loop-active)" "no"

# Red build: announce, but leave the flag so the run can resume once it is fixed.
reset; : > .claude/.loop-active
KAPP_LOOP_FAKE_VERIFY=fail run >/dev/null
KAPP_LOOP_FAKE_VERIFY=fail run >/dev/null
chk "red build keeps the flag for resume" "$(exists .claude/.loop-active)" "yes"

# Whatever is emitted has to be parseable, or Claude Code ignores it and the loop
# silently dies -- exactly the failure these announcements are meant to prevent.
reset; : > .claude/.loop-active; echo 99 > .claude/.loop-count
if run | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  chk "emitted hook payload is valid JSON" yes yes
else
  chk "emitted hook payload is valid JSON" no yes
fi

[ "$FAILED" -eq 0 ] && echo "loop-guard: all green" || echo "loop-guard: FAILURES"
exit "$FAILED"
