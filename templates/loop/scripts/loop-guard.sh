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
CAP="${KAPP_LOOP_CAP:-25}"

# --- 1. infinite-loop guard: bail if we're already continuing from a stop hook ---
INPUT="$(cat 2>/dev/null || true)"
case "$INPUT" in
  *'"stop_hook_active":true'* | *'"stop_hook_active": true'*) exit 0 ;;
esac

# --- 2. loop off by default ---
[ -f "$FLAG" ] || exit 0

# --- 3. iteration cap ---
COUNT=0
[ -f "$COUNT_FILE" ] && COUNT="$(cat "$COUNT_FILE" 2>/dev/null || echo 0)"
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNT_FILE"
if [ "$COUNT" -gt "$CAP" ]; then
  rm -f "$FLAG"
  echo "loop-guard: iteration cap ($CAP) reached — stopping the loop and removing the flag." >&2
  exit 0
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
    exit 0
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
  exit 0
fi

# --- 5/6. gate passed: continue if work remains, else finish ---
if [ -f "PLAN.md" ] && grep -q '^[[:space:]]*-[[:space:]]\[ \]' "PLAN.md"; then
  REASON="Verification gate passed. The self-improve loop is active and PLAN.md still has unchecked items. Continue: take the next \`- [ ]\` item in PLAN.md, follow AiGuidelines/loop/SELF_IMPROVE_LOOP.md (implement smallest change -> spawn relevant specialists to review -> synthesize & log decisions -> run the tiered gate -> only on green, check the box and commit). Work exactly one item, then end your turn."
  printf '{"decision":"block","reason":"%s"}\n' "$REASON"
  exit 0
fi

# No unchecked items remain (or no PLAN.md): the run is complete. The workflow already wrote the
# report; turn the loop off.
rm -f "$FLAG"
echo "loop-guard: PLAN.md has no unchecked items — loop complete, flag removed." >&2
exit 0
