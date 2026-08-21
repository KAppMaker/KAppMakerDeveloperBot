#!/bin/sh
# Tests for the specialist-agent set: frontmatter validity, installer sync,
# and routing-list drift.
#
# The drift class this guards against is real: design-fidelity-reviewer shipped
# in the AGENTS list and IMPROVEMENT_PASS but was absent from both routing
# lists (SELF_IMPROVE_LOOP.md step 3 and orchestrator.md), so the orchestrator
# never learned it existed. Frontmatter, installer list and routing lists are
# three copies of one fact; these tests pin them together.
#
# Run: sh provision/agents.test.sh
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
AGENTS_DIR="$ROOT/templates/loop/.claude/agents"
INSTALL_SH="$ROOT/provision/agents-install.sh"
LOOP_MD="$ROOT/templates/loop/AiGuidelines/loop/SELF_IMPROVE_LOOP.md"
ORCH_MD="$AGENTS_DIR/orchestrator.md"

pass=0; fail=0

ok()   { pass=$((pass+1)); printf 'ok   - %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf 'FAIL - %s\n' "$1"; }
check(){ if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }

# ---- 1. Every agent file has valid frontmatter, name matching its filename
for f in "$AGENTS_DIR"/*.md; do
  base="$(basename "$f" .md)"
  [ "$(head -n1 "$f")" = "---" ]; check $? "$base: frontmatter opens with ---"
  grep -q "^name: $base\$" "$f"; check $? "$base: name matches filename"
  grep -q "^description: ." "$f"; check $? "$base: has a description"
done

# ---- 2. Bidirectional sync with the installer's AGENTS list
agents_line="$(grep '^AGENTS=' "$INSTALL_SH" | sed 's/^AGENTS="//; s/"$//')"
[ -n "$agents_line" ]; check $? "installer has an AGENTS list"

for f in "$AGENTS_DIR"/*.md; do
  base="$(basename "$f" .md)"
  case " $agents_line " in
    *" $base "*) ok "installer AGENTS includes $base" ;;
    *) bad "installer AGENTS missing $base — new agent never reaches existing boxes" ;;
  esac
done

for name in $agents_line; do
  if [ -f "$AGENTS_DIR/$name.md" ]; then
    ok "AGENTS entry $name has a template file"
  else
    bad "AGENTS entry $name has no template file — install will 404"
  fi
done

# ---- 3. Routing-drift guard: every reviewer appears in both routing lists.
# orchestrator and prompt-architect are not reviewers (one dispatches, one
# runs pre-implementation), so they are exempt.
for f in "$AGENTS_DIR"/*.md; do
  base="$(basename "$f" .md)"
  case "$base" in orchestrator|prompt-architect) continue ;; esac
  grep -q "$base" "$LOOP_MD"; check $? "SELF_IMPROVE_LOOP routing mentions $base"
  grep -q "$base" "$ORCH_MD"; check $? "orchestrator routing mentions $base"
done

# prompt-architect must still be discoverable from both docs, as intake.
grep -q "prompt-architect" "$LOOP_MD"; check $? "SELF_IMPROVE_LOOP mentions prompt-architect intake"
grep -q "prompt-architect" "$ORCH_MD"; check $? "orchestrator mentions prompt-architect intake"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
