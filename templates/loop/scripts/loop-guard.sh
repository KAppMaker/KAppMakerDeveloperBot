#!/bin/sh
# loop-guard.sh — Stop hook for the KAppMaker self-improving dev loop.
#
# Registered in .claude/settings.json under hooks.Stop. Fires when Claude finishes a turn.
# It is INERT unless the loop has been explicitly started (flag file present), so normal
# sessions stop normally.
#
# Behavior:
#   - stop_hook_active in the hook payload  -> exit 0 (mandatory infinite-loop guard)
#   - flag file .claude/.loop-active absent  -> exit 0 (loop is OFF by default)
#   - iteration count over cap               -> remove flag, exit 0
#   - run tiered Gradle gate; on failure     -> stop (exit 0), leave flag for resume (never green a red build)
#   - gate passes AND PLAN.md has "- [ ]"    -> emit {"decision":"block","reason":...} to continue
#   - gate passes AND no "- [ ]" remain      -> remove flag, exit 0 (run is complete)
#
# Output protocol (Claude Code Stop hook): print {"decision":"block","reason":"..."} on stdout
# (exit 0) to force another iteration. Anything else with exit 0 lets the session stop.

set -u

# --- locate project root (where .claude/ lives) ---
DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$DIR" 2>/dev/null || exit 0

FLAG=".claude/.loop-active"
COUNT_FILE=".claude/.loop-count"
BASE_FILE=".claude/.loop-base"
# The cap is a runaway backstop, not a work limit. A full improvement pass across six
# milestones routinely produces well over a hundred plan items, and a cap of 25 used to
# end the night about a quarter of the way through — the owner woke up to a run that had
# stopped for no reason they could see. What actually needs catching is a loop that stops
# making progress, which STALL_CAP below does directly.
CAP="${KAPP_LOOP_CAP:-200}"
# Consecutive iterations allowed with no drop in the number of unchecked PLAN.md items.
STALL_CAP="${KAPP_LOOP_STALL_CAP:-8}"
REMAIN_FILE=".claude/.loop-remaining"
STALL_FILE=".claude/.loop-stall"

# --- announce-then-stop ---------------------------------------------------
# Three of the four stop paths used to be silent, which is why a stalled run and
# a finished run looked identical from the owner's phone. Force one final turn so
# the agent can say what happened, then stop for real on the next pass.
# $1 = what to tell the owner. $2 = "keep-flag" to leave the loop resumable (red build),
# anything else clears it. The flag is cleared HERE, on the second pass — a caller that
# cleared it first would trip the "loop off" check above and never announce anything.
ANNOUNCED=".claude/.loop-announced"
announce_then_stop() {
  if [ -f "$ANNOUNCED" ]; then
    rm -f "$ANNOUNCED"
    [ "${2:-}" = "keep-flag" ] || rm -f "$FLAG" "$COUNT_FILE" "$REMAIN_FILE" "$STALL_FILE"
    exit 0
  fi
  : > "$ANNOUNCED"
  printf '{"decision":"block","reason":"%s"}\n' "$1"
  exit 0
}


# --- 1. infinite-loop guard: bail if we're already continuing from a stop hook ---
INPUT="$(cat 2>/dev/null || true)"
case "$INPUT" in
  *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;;
esac

# --- 2. loop off by default ---
[ -f "$FLAG" ] || { rm -f ".claude/.loop-announced" 2>/dev/null; exit 0; }

# --- 3. iteration cap ---
COUNT=0
[ -f "$COUNT_FILE" ] && COUNT="$(cat "$COUNT_FILE" 2>/dev/null || echo 0)"
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"
if [ "$COUNT" -gt "$CAP" ]; then
  echo "loop-guard: iteration cap ($CAP) reached — stopping the loop and removing the flag." >&2
  announce_then_stop "The improvement run hit its iteration cap of $CAP passes, so it is stopping here rather than running forever. Send the owner one short message: what you finished, what is still open, and that they can say continue to start a fresh run. Then stop."
fi

# --- detect Gradle root: ./gradlew, else MobileApp/gradlew ---
GRADLE_ROOT=""
if [ -x "./gradlew" ] || [ -f "./gradlew" ]; then
  GRADLE_ROOT="."
elif [ -x "./MobileApp/gradlew" ] || [ -f "./MobileApp/gradlew" ]; then
  GRADLE_ROOT="MobileApp"
fi

# --- 4. tiered verification gate ---
# Test hook: KAPP_LOOP_FAKE_VERIFY=pass|fail|skip lets the dry-run harness exercise the logic
# without invoking Gradle.
VERIFY_RESULT="run"
case "${KAPP_LOOP_FAKE_VERIFY:-}" in
  pass) VERIFY_RESULT="pass" ;;
  fail) VERIFY_RESULT="fail" ;;
  skip) VERIFY_RESULT="pass" ;;  # treat as a no-op pass
esac

if [ "$VERIFY_RESULT" = "run" ]; then
  if [ -z "$GRADLE_ROOT" ]; then
    echo "loop-guard: no gradlew found (looked at ./ and ./MobileApp) — cannot verify, stopping." >&2
    announce_then_stop "The loop cannot find a Gradle wrapper here, so it has no way to verify a change is safe and is stopping. Tell the owner in one short message that this project is missing its build setup and nothing was changed." keep-flag
  fi

  # Determine which files changed for this item: last commit + any uncommitted changes.
  CHANGED="$(
    {
      git diff --name-only HEAD~1 HEAD 2>/dev/null
      git diff --name-only 2>/dev/null
      git diff --name-only --cached 2>/dev/null
    } | sort -u
  )"

  # UI tier if any changed path is under presentation/ or designsystem/, matches *Screen*.kt,
  # or a changed .kt file contains @Preview.
  UI_CHANGED=0
  if printf '%s\n' "$CHANGED" | grep -Eq '(^|/)(presentation|designsystem)/|Screen[^/]*\.kt$'; then
    UI_CHANGED=1
  fi
  if [ "$UI_CHANGED" -eq 0 ]; then
    for f in $CHANGED; do
      case "$f" in
        *.kt)
          [ -f "$f" ] && grep -q '@Preview' "$f" 2>/dev/null && { UI_CHANGED=1; break; } ;;
      esac
    done
  fi

  (
    cd "$GRADLE_ROOT" || exit 1
    ./gradlew spotlessApply  --quiet || exit 1
    ./gradlew spotlessCheck  --quiet || exit 1
    ./gradlew :shared:jvmTest --quiet || exit 1
    if [ "$UI_CHANGED" -eq 1 ]; then
      ./gradlew :shared:testAndroidHostTest --quiet || exit 1
      ./gradlew :shared:verifyRoborazziAndroidHostTest --quiet || exit 1
    fi
  )
  if [ "$?" -ne 0 ]; then
    VERIFY_RESULT="fail"
  else
    VERIFY_RESULT="pass"
  fi
fi

if [ "$VERIFY_RESULT" = "fail" ]; then
  # Never green a red build, never loop past it. Stop and leave the flag so a human/next message
  # can resume after the failure is fixed.
  echo "loop-guard: verification gate FAILED — stopping the loop (flag left in place for resume)." >&2
  echo "Fix the failing build/tests before continuing. The current PLAN.md item was NOT checked off." >&2
  announce_then_stop "The build or tests went red, so the loop stopped rather than checking off work on a broken build. Send the owner one short message in plain words: what broke, whether you can fix it, and what you need from them if you cannot. Then stop." keep-flag
fi

# --- 4b. stall detection ---
# Count what is left. If that number has not gone down for STALL_CAP iterations in a row,
# the loop is chewing on something it cannot finish — burning the owner's Claude quota all
# night on no progress. That is the real runaway, and it is invisible to a plain counter.
REMAINING=0
if [ -f "PLAN.md" ]; then
  REMAINING="$(grep -c '^[[:space:]]*-[[:space:]]\[ \]' "PLAN.md" 2>/dev/null || echo 0)"
fi
PREV_REMAINING=-1
[ -f "$REMAIN_FILE" ] && PREV_REMAINING="$(cat "$REMAIN_FILE" 2>/dev/null || echo -1)"
echo "$REMAINING" > "$REMAIN_FILE"

STALL=0
[ -f "$STALL_FILE" ] && STALL="$(cat "$STALL_FILE" 2>/dev/null || echo 0)"
if [ "$PREV_REMAINING" -ge 0 ] && [ "$REMAINING" -ge "$PREV_REMAINING" ]; then
  STALL=$((STALL + 1))
else
  STALL=0
fi
echo "$STALL" > "$STALL_FILE"

if [ "$STALL" -ge "$STALL_CAP" ]; then
  echo "loop-guard: no progress for $STALL iterations — stopping the loop." >&2
  announce_then_stop "The run has gone $STALL passes without finishing a single plan item, so it is stopping instead of burning the night on something it cannot get past. Send the owner one short message: which item you are stuck on, what you tried, and what you need from them. Then stop."
fi

# --- 5/6. gate passed: continue if work remains, else finish ---
if [ -f "PLAN.md" ] && grep -q '^[[:space:]]*-[[:space:]]\[ \]' "PLAN.md"; then
  REASON="Verification gate passed. The self-improve loop is active and PLAN.md still has unchecked items. Continue: take the next \`- [ ]\` item in PLAN.md, follow AiGuidelines/loop/SELF_IMPROVE_LOOP.md (implement smallest change -> spawn relevant specialists to review -> synthesize & log decisions -> run the tiered gate -> only on green, check the box and commit). Work exactly one item, then end your turn."
  rm -f "$ANNOUNCED"
  printf '{"decision":"block","reason":"%s"}\n' "$REASON"
  exit 0
fi

# No unchecked items remain (or no PLAN.md): the run is complete. The workflow already wrote the
# report; turn the loop off.
echo "loop-guard: PLAN.md has no unchecked items — loop complete, flag removed." >&2
announce_then_stop "Every item in PLAN.md is done and the build is green. Send the owner one short message: what you improved and what it means for someone using the app. Plain words, no jargon. Then stop."
