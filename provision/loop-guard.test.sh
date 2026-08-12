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
# A prefix assignment on a *function* call persists in the shell afterwards in POSIX sh
# (unlike on an external command), so "KAPP_LOOP_FAKE_VERIFY=fail run" silently left the
# gate failing for every later case. Keep the failing variant in its own subshell.
run_redbuild() { ( KAPP_LOOP_FAKE_VERIFY=fail; export KAPP_LOOP_FAKE_VERIFY; run "$@" ); }
blocked() { case "$1" in *'"decision":"block"'*) echo yes ;; *) echo no ;; esac; }
exists() { [ -f "$1" ] && echo yes || echo no; }

reset() {
  rm -f .claude/.loop-active .claude/.loop-count .claude/.loop-announced \
        .claude/.loop-remaining .claude/.loop-stall
}

# Drive the caps from the environment rather than the defaults. The defaults are
# deliberately large (a real overnight run does hundreds of passes), so a test that
# hardcoded a number next to them silently stopped testing anything the day the
# default moved.
export KAPP_LOOP_CAP=5
export KAPP_LOOP_STALL_CAP=3

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
printf -- "- [ ] still open\n" > PLAN.md
OUT="$(run)"
chk "cap announces" "$(blocked "$OUT")" "yes"
case "$OUT" in *"iteration cap"*) chk "cap says why" yes yes ;; *) chk "cap says why" no yes ;; esac
run >/dev/null
chk "cap clears the flag" "$(exists .claude/.loop-active)" "no"

# Red build: announce, but leave the flag so the run can resume once it is fixed.
reset; : > .claude/.loop-active
run_redbuild >/dev/null
run_redbuild >/dev/null
chk "red build keeps the flag for resume" "$(exists .claude/.loop-active)" "yes"

# A loop that keeps passing the gate but never finishes an item is the real runaway:
# it burns the owner's Claude quota all night on nothing. A plain iteration counter
# cannot see it, so it is caught by watching the unchecked count instead.
reset; : > .claude/.loop-active
printf -- "- [ ] one\n- [ ] two\n" > PLAN.md
i=0
STALL_OUT=""
while [ "$i" -le "$KAPP_LOOP_STALL_CAP" ]; do
  STALL_OUT="$(run)"
  i=$((i + 1))
done
case "$STALL_OUT" in *"without finishing"*) chk "stall is caught" yes yes ;; *) chk "stall is caught" no yes ;; esac
run >/dev/null
chk "stall stops the loop" "$(exists .claude/.loop-active)" "no"

# ...but real progress must reset the stall counter, or a slow item would look like a stall.
reset; : > .claude/.loop-active
printf -- "- [ ] one\n- [ ] two\n- [ ] three\n" > PLAN.md
run >/dev/null
printf -- "- [x] one\n- [ ] two\n- [ ] three\n" > PLAN.md
run >/dev/null
chk "progress resets the stall counter" "$(cat .claude/.loop-stall 2>/dev/null)" "0"

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
