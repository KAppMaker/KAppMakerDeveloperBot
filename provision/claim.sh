#!/usr/bin/env bash
# kappmaker-claim — shared status board: which always-on worker is on which project.
#
# WHY: workers (app1, app2, …) share one ~/projects folder and cannot see each
# other's sessions. Without a shared record, two agents can silently edit the
# same project and corrupt each other's work.
#
# DELIBERATELY ADVISORY, NOT A LOCK. `take` never fails and never blocks. A hard
# lock would be worse than the problem: a worker that crashes mid-task would
# leave a claim nobody can clear, and the other worker would refuse to work
# forever with no way to tell whether the task finished or died. So this records
# and reports; the human decides. Stale entries are harmless — worst case the
# board is out of date, and the next `take` overwrites it.
#
# Usage:
#   kappmaker-claim take    <worker> <project>   # record; warns if someone else had it
#   kappmaker-claim release <worker> <project>   # optional bookkeeping when done
#   kappmaker-claim who     <project>
#   kappmaker-claim list                         # the whole board

set -uo pipefail

CLAIMS_DIR="${KAPPMAKER_CLAIMS_DIR:-$HOME/projects/.kappmaker-claims}"

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
  exit 64
}

# Projects are directory names; keep them to a safe charset so a claim entry can
# never escape the claims dir.
valid_name() { [[ "$1" =~ ^[A-Za-z0-9._-]+$ ]]; }

claim_owner() {
  [[ -f "$CLAIMS_DIR/$1/owner" ]] && cat "$CLAIMS_DIR/$1/owner"
}

cmd_take() {
  local worker="$1" project="$2"
  valid_name "$worker" && valid_name "$project" || { echo "invalid worker/project name" >&2; exit 64; }

  local previous
  previous="$(claim_owner "$project")"

  mkdir -p "$CLAIMS_DIR/$project"
  printf '%s\n' "$worker" > "$CLAIMS_DIR/$project/owner"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$CLAIMS_DIR/$project/since"

  if [[ -n "$previous" && "$previous" != "$worker" ]]; then
    # Reported, not refused — the agent relays this to the human, who decides.
    echo "NOTE: $project was last claimed by $previous. You are now recorded as working on it."
    echo "Tell the user another helper may still be on this project before making changes."
    return 0
  fi

  echo "recorded: $project -> $worker"
}

cmd_release() {
  local worker="$1" project="$2"
  valid_name "$worker" && valid_name "$project" || { echo "invalid worker/project name" >&2; exit 64; }

  [[ -d "$CLAIMS_DIR/$project" ]] || { echo "not claimed: $project"; return 0; }

  # Anyone may clear an entry. Refusing here would recreate the stuck state this
  # tool exists to avoid.
  rm -rf "${CLAIMS_DIR:?}/$project"
  echo "released: $project (was $worker)"
}

cmd_who() {
  local owner
  owner="$(claim_owner "$1")"
  [[ -n "$owner" ]] && { echo "$owner"; return 0; }
  echo "unclaimed"
}

cmd_list() {
  [[ -d "$CLAIMS_DIR" ]] || { echo "no claims"; return 0; }

  local found=0 dir project owner since
  for dir in "$CLAIMS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    found=1
    project="$(basename "$dir")"
    owner="$(cat "$dir/owner" 2>/dev/null || echo '?')"
    since="$(cat "$dir/since" 2>/dev/null || echo '?')"
    printf '%-30s %-8s since %s\n' "$project" "$owner" "$since"
  done

  [[ "$found" -eq 1 ]] || echo "no claims"
}

case "${1:-}" in
  take)    [[ $# -eq 3 ]] || usage; cmd_take "$2" "$3" ;;
  release) [[ $# -eq 3 ]] || usage; cmd_release "$2" "$3" ;;
  who)     [[ $# -eq 2 ]] || usage; cmd_who "$2" ;;
  list)    cmd_list ;;
  *)       usage ;;
esac
