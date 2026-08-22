#!/bin/sh
# Tests for templates/bin/kappmaker-model against a throwaway HOME.
# Run: sh provision/model.test.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/templates/bin/kappmaker-model"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export CLAUDE_HOME="$T/.claude" PROJECTS_DIR="$T/projects" KAPPMAKER_MODEL_RESTART_CMD="echo RESTARTED > $T/restarted"
mkdir -p "$CLAUDE_HOME/agents" "$PROJECTS_DIR/App/.claude/agents"
printf -- '---\nname: orchestrator\ndescription: x\nmodel: fable\neffort: high\n---\nbody\n' > "$CLAUDE_HOME/agents/orchestrator.md"
printf -- '---\nname: prompt-architect\ndescription: x\nmodel: fable\neffort: high\n---\nbody\n' > "$CLAUDE_HOME/agents/prompt-architect.md"
printf -- '---\nname: qa-engineer\ndescription: x\nmodel: opus\neffort: medium\n---\nbody\n' > "$CLAUDE_HOME/agents/qa-engineer.md"
cp "$CLAUDE_HOME/agents/orchestrator.md" "$PROJECTS_DIR/App/.claude/agents/orchestrator.md"
printf '{"hooks":{}}\n' > "$CLAUDE_HOME/settings.json"

pass=0; fail=0
ok(){ pass=$((pass+1)); printf 'ok   - %s\n' "$1"; }
bad(){ fail=$((fail+1)); printf 'FAIL - %s\n' "$1"; }
check(){ if [ "$1" = 0 ]; then ok "$2"; else bad "$2"; fi; }

"$BIN" show | grep -q "session: default"; check $? "show reports default session model when unset"

"$BIN" session opus >/dev/null
grep -q '"model": "opus"' "$CLAUDE_HOME/settings.json"; check $? "session opus writes settings.json model"
grep -q '"hooks"' "$CLAUDE_HOME/settings.json"; check $? "session switch preserves other settings keys"
[ ! -f "$T/restarted" ]; check $? "session switch without --restart does not restart"
"$BIN" session fable --restart >/dev/null
[ -f "$T/restarted" ]; check $? "session --restart runs the restart command"
"$BIN" session default >/dev/null
grep -q '"model"' "$CLAUDE_HOME/settings.json"; [ $? = 1 ]; check $? "session default removes the model key"
"$BIN" session bogus >/dev/null 2>&1; [ $? != 0 ]; check $? "unknown alias is rejected"

"$BIN" downshift "weekly cap" >/dev/null
grep -q '^model: opus' "$CLAUDE_HOME/agents/orchestrator.md"; check $? "downshift moves orchestrator to opus"
grep -q '^model: opus' "$CLAUDE_HOME/agents/prompt-architect.md"; check $? "downshift moves prompt-architect to opus"
grep -q '^model: opus' "$CLAUDE_HOME/agents/qa-engineer.md"; check $? "downshift leaves non-fable-tier agents alone"
grep -q '^effort: high' "$CLAUDE_HOME/agents/orchestrator.md"; check $? "downshift keeps effort untouched"
grep -q '^model: opus' "$PROJECTS_DIR/App/.claude/agents/orchestrator.md"; check $? "downshift syncs project-local agent copies"
grep -q 'weekly cap' "$CLAUDE_HOME/kappmaker-model.state"; check $? "downshift records the reason"
"$BIN" show 2>&1 | grep -q "downshifted"; check $? "show surfaces the downshifted state"

"$BIN" restore >/dev/null
grep -q '^model: fable' "$CLAUDE_HOME/agents/orchestrator.md"; check $? "restore moves orchestrator back to fable"
[ ! -f "$CLAUDE_HOME/kappmaker-model.state" ]; check $? "restore clears the state file"

"$BIN" agents sonnet qa-engineer >/dev/null
grep -q '^model: sonnet' "$CLAUDE_HOME/agents/qa-engineer.md"; check $? "agents <alias> <name> targets a named agent"
grep -q '^model: fable' "$CLAUDE_HOME/agents/orchestrator.md"; check $? "named agents switch does not touch others"
"$BIN" agents best >/dev/null 2>&1; [ $? != 0 ]; check $? "'best' is rejected for agents"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
