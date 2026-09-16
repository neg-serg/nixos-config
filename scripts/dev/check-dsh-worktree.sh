#!/usr/bin/env bash
# Regression gate for packages/local-bin/bin/dsh-worktree.
#
# The helper creates real git worktrees *outside* the repository so parallel dsh
# sessions never fight over the working copy. What this pins:
#
#   * the main checkout's `git status` stays clean after worktrees are created
#     (the whole point of keeping them out of the tree);
#   * each worktree gets its own branch and its own populated checkout;
#   * name/branch collisions and running outside a repository fail loudly;
#   * a dirty worktree is not removed without --force, and --force does remove it;
#   * --copy brings gitignored files in, DSH_WORKTREE_POST_CREATE runs in the
#     new tree.
#
# Usage: check-dsh-worktree.sh [dsh-worktree-path]
#
# Without an argument the helper is taken from this repository.
#
# NOTE: no `set -e`. A failing assertion must be reported and the run must
# continue, so every check captures its status explicitly; a first failure
# aborting the script would hide the remaining ones.

set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="${1:-$here/../../packages/local-bin/bin/dsh-worktree}"

if [ ! -f "$BIN" ]; then
  echo "check-dsh-worktree: no such helper: $BIN" >&2
  exit 1
fi

# Run through the interpreter when the source tree has not kept the exec bit
# (the deployed copy under ~/.local/bin is always executable).
run() {
  if [ -x "$BIN" ]; then "$BIN" "$@"; else sh "$BIN" "$@"; fi
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export DSH_WORKTREE_ROOT="$work/trees"
repo="$work/repo"
mkdir -p "$DSH_WORKTREE_ROOT" "$repo"

# Counters, assertions and the footer live in the shared dev helper (lib.sh).
# shellcheck source-path=SCRIPTDIR source=lib.sh
. "$here/lib.sh"

sh -n "$BIN"
assert $? "the helper parses as POSIX sh"

cd "$repo" || exit 1
git init -q -b main .
git config user.email check@dsh-worktree
git config user.name check-dsh-worktree
printf '*.env\n' > .gitignore
printf 'secret\n' > .env
printf 'hi\n' > a.txt
git add -A
git commit -qm init

run --help > /dev/null
assert $? "--help exits 0"
run --help 2>&1 | grep -q "git worktrees for parallel dsh sessions"
assert $? "--help prints the usage header"

base="$DSH_WORKTREE_ROOT/$(basename "$repo")-$(printf '%s' "$repo" | sha1sum | cut -c1-8)"

out="$(run new task1 --open print)"
assert $? "new task1 exits 0"
check test "$out" = "$base/task1"
assert $rc "new prints the worktree path on stdout"
check test -f "$base/task1/a.txt"
assert $rc "the worktree is a populated checkout"
git show-ref --verify --quiet refs/heads/wt/task1
assert $? "branch wt/task1 exists"
check test "$(git -C "$base/task1" rev-parse --abbrev-ref HEAD)" = "wt/task1"
assert $rc "the worktree is on its own branch"
check test -z "$(git status --porcelain)"
assert $rc "the main checkout's git status stays clean"

run list | grep -q '^task1'
assert $? "list shows the worktree"
check test "$(run path task1)" = "$base/task1"
assert $rc "path prints the worktree directory"

run new task1 --open print > /dev/null 2>&1
assert_fails $? "a duplicate name is rejected"
run new 'bad/name' --open print > /dev/null 2>&1
assert_fails $? "a slash in the name is rejected"
run new 'bad name' --open print > /dev/null 2>&1
assert_fails $? "a space in the name is rejected"
run new --force --open print > /dev/null 2>&1
assert_fails $? "a leading dash is rejected (a mistyped flag cannot become a name)"
run new other --branch wt/task1 --open print > /dev/null 2>&1
assert_fails $? "an existing branch is rejected"
(cd "$work" && run new outsider --open print > /dev/null 2>&1)
assert_fails $? "running outside a repository is rejected"

run new task2 --open print --copy .env > /dev/null
assert $? "new --copy exits 0"
check test -f "$base/task2/.env"
assert $rc "--copy brought the gitignored file into the worktree"

DSH_WORKTREE_POST_CREATE='touch hook-ran' run new task3 --open print > /dev/null
assert $? "new with DSH_WORKTREE_POST_CREATE exits 0"
check test -f "$base/task3/hook-ran"
assert $rc "the post-create hook ran inside the new worktree"

run rm task1 > /dev/null
assert $? "rm removes a clean worktree"
check test '!' -d "$base/task1"
assert $rc "the worktree directory is gone"
git show-ref --verify --quiet refs/heads/wt/task1
assert $? "rm keeps the branch (only the tree goes)"
run rm task1 > /dev/null 2>&1
assert_fails $? "rm of a missing worktree fails"
printf 'dirty\n' > "$base/task2/dirty.txt"
run rm task2 > /dev/null 2>&1
assert_fails $? "rm refuses a dirty worktree"
run rm task2 --force > /dev/null
assert $? "rm --force removes it"
run prune > /dev/null
assert $? "prune exits 0"
check test -z "$(git status --porcelain)"
assert $rc "the main checkout is still clean at the end"

summary "check-dsh-worktree"
