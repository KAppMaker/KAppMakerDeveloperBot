#!/bin/sh
# start-loop.sh — begin the KAppMaker self-improving dev loop.
#
# Called when Claude recognizes a human "start" intent (see CLAUDE.loop.md). It is the only thing
# that turns the loop ON. Mechanical only — the decision to start is conversational.
#
# Usage: scripts/start-loop.sh "<goal text>"
#
# Steps:
#   1. git checkpoint (commit any pending work so each item starts from a clean tree).
#   2. record the base commit (for tier detection / resume).
#   3. seed PLAN.md from PLAN.template.md if no plan exists, injecting <goal>.
#   4. reset the iteration counter and create the .loop-active flag.

set -u

DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$DIR" || exit 1

GOAL="${1:-improve conversion (free->paid and credit-pack)}"
mkdir -p .claude

# 1. checkpoint pending work (no-op if nothing to commit)
if git rev-parse --git-dir >/dev/null 2>&1; then
  if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
    git add -A
    git commit -m "chore: checkpoint before self-improve loop" >/dev/null 2>&1 || true
  fi
  # 2. record base commit
  git rev-parse HEAD > .claude/.loop-base 2>/dev/null || true
fi

# 3. seed PLAN.md if absent
TEMPLATE_PLAN="AiGuidelines/loop/PLAN.template.md"
if [ ! -f "PLAN.md" ]; then
  if [ -f "$TEMPLATE_PLAN" ]; then
    sed "s|<goal>|$GOAL|g" "$TEMPLATE_PLAN" > PLAN.md
  else
    {
      echo "# PLAN — $GOAL"
      echo
      echo "- [ ] Decompose the goal into verifiable items (orchestrator)"
    } > PLAN.md
  fi
  echo "start-loop: seeded PLAN.md from template for goal: $GOAL"
else
  echo "start-loop: PLAN.md already exists — keeping it (resuming)."
fi

# 4. reset counter + raise the flag
echo 0 > .claude/.loop-count
: > .claude/.loop-active

echo "start-loop: loop ACTIVE. Goal: $GOAL"
echo "start-loop: orchestrator should now tailor PLAN.md to the goal and begin the top item."
