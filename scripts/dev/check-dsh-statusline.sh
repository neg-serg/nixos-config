#!/usr/bin/env bash
# Regression gate for packages/local-bin/bin/dsh-statusline.
#
# The script is the content half of the status line: a host pipes session JSON to
# its stdin and renders the first stdout line. What this pins:
#
#   * protocol mode reads the documented payload subset and degrades when fields
#     are missing (a status line must never fail the session);
#   * the git segment reports the branch, the three dirty counts and identifies a
#     dsh-worktree tree by name;
#   * context is rendered from ratio, or from tokens/max when only those exist;
#   * DSH_STATUSLINE_PARTS can narrow the line to a subset of segments;
#   * --git / --demo / --help are separate, working modes.
#
# Usage: check-dsh-statusline.sh [dsh-statusline-path]

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${1:-$here/../../packages/local-bin/bin/dsh-statusline}"

if [ ! -f "$BIN" ]; then
  echo "check-dsh-statusline: no such script: $BIN" >&2
  exit 1
fi

run() { sh "$BIN" "$@"; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

pass=0
fail=0
assert() {
  if [ "$1" -eq 0 ]; then
    pass=$((pass + 1))
    echo "  ok   $2"
  else
    fail=$((fail + 1))
    echo "  FAIL $2"
  fi
}
assert_fails() {
  if [ "$1" -ne 0 ]; then
    pass=$((pass + 1))
    echo "  ok   $2"
  else
    fail=$((fail + 1))
    echo "  FAIL $2"
  fi
}
rc=0
check() {
  "$@"
  rc=$?
}
contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac }
not_contains() { case "$1" in *"$2"*) return 1 ;; *) return 0 ;; esac }

sh -n "$BIN"
assert $? "the script parses as POSIX sh"

# ── fixture: a dirty repository ──────────────────────────────────────────────
repo="$work/repo"
mkdir -p "$repo"
cd "$repo" || exit 1
git init -q -b main .
git config user.email check@dsh-statusline
git config user.name check-dsh-statusline
printf 'one\n' > tracked.txt
printf 'two\n' > staged.txt
git add -A
git commit -qm init
printf 'one changed\n' > tracked.txt
printf 'two changed\n' > staged.txt
git add staged.txt
printf 'fresh\n' > untracked.txt

payload() {
  printf '{"session_id":"s1","turn":7,"workspace":{"current_dir":"%s"}%s}' "$1" "$2"
}

line="$(payload "$repo" '' | run)"
assert $? "protocol mode exits 0"
check contains "$line" "⎇ main"
assert $rc "the branch is in the line"
check contains "$line" "✚1"
assert $rc "one modified file is counted"
check contains "$line" "◆1"
assert $rc "one staged file is counted"
check contains "$line" "?1"
assert $rc "one untracked file is counted"
check contains "$line" "turn 7"
assert $rc "the turn is in the line"

check contains "$(payload "$repo" ',"context":{"ratio":0.42}' | run)" "ctx 42%"
assert $rc "context.ratio becomes a percentage"
check contains "$(payload "$repo" ',"context":{"estimated_tokens":54000,"max_tokens":128000}' | run)" "ctx 42%"
assert $rc "tokens/max become a percentage when ratio is absent"

check contains "$(payload "$repo" '' | DSH_STATUSLINE_PARTS=turn run)" "turn 7"
assert $rc "DSH_STATUSLINE_PARTS keeps a requested segment"
parts_line="$(payload "$repo" '' | DSH_STATUSLINE_PARTS=turn run)"
check not_contains "$parts_line" "main"
assert $rc "DSH_STATUSLINE_PARTS drops the others"

# A payload with nothing usable still prints exactly one line.
check test "$(printf '{}' | run | wc -l)" -eq 1
assert $rc "an empty payload prints a single line"
check test -n "$(printf '{}' | run)"
assert $rc "an empty payload never prints an empty line"

# A worktree tree is identified by name, not by branch.
root="$work/trees"
wt="$root/repo-abc12345/task-1"
mkdir -p "$wt"
check contains "$(payload "$wt" '' | run)" "task-1"
assert $rc "a directory outside the tree root falls back to its own name"
check contains "$(payload "$wt" '' | DSH_WORKTREE_ROOT="$root" run)" "wt:task-1"
assert $rc "a tree under DSH_WORKTREE_ROOT is named by its worktree"

# ── the other modes ──────────────────────────────────────────────────────────
check contains "$(run --git "$repo")" "⎇ main"
assert $rc "--git prints the git segment for a directory"
check test -n "$(run --demo)"
assert $rc "--demo runs the protocol against a canned payload"
run --help > /dev/null 2>&1
assert $? "--help exits 0"
run --nope > /dev/null 2>&1
assert_fails $? "an unknown option fails"

echo
echo "check-dsh-statusline: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
