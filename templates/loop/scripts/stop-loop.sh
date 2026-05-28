#!/bin/sh
# stop-loop.sh — turn the KAppMaker self-improving dev loop OFF.
#
# Called when Claude recognizes a human "stop" intent (see CLAUDE.loop.md), and also by
# loop-guard.sh when the run completes. Removes the flag so the Stop hook goes inert again.
# Already-committed work is left intact; nothing is reverted.

set -u

DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$DIR" || exit 1

if [ -f ".claude/.loop-active" ]; then
  rm -f ".claude/.loop-active"
  echo "stop-loop: loop stopped (flag removed). Committed work is preserved."
else
  echo "stop-loop: loop was not active — nothing to do."
fi
