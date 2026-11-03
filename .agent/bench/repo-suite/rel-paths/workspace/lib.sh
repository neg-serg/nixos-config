#!/usr/bin/env bash
# Shared helpers for the scripts/dev gates. Source it; never execute it.
# Source after `set -uo pipefail`: the counters and $rc are globals by design.

# Print the repository root: the $1 override, else the git top level, else cwd.
repo_root() {
  printf '%s\n' "${1:-$(git rev-parse --show-toplevel 2> /dev/null || pwd)}"
}

# ── assertion harness for the dsh regression gates ──────────────────────────
pass=0
fail=0
rc=0

# Assert the status passed in $1 (assert: 0 = pass; assert_fails: non-zero = pass).
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

# check: run a test command and stash its status in $rc — `ok $?` after a test
# is both a shellcheck warning (SC2319) and fragile under `set -e`.
# shellcheck disable=SC2034  # $rc is read by the sourcing gate, not in here
check() {
  "$@"
  rc=$?
}

contains() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac }
not_contains() { case "$1" in *"$2"*) return 1 ;; *) return 0 ;; esac }

# Print the footer for gate $1; the return status is the gate's status.
summary() {
  echo
  echo "$1: $pass passed, $fail failed"
  [ "$fail" -eq 0 ]
}

# Resolve a tool the pleamar gates need: $1 on PATH first, else the flake output
# of the same name (built with `--option substitute false`, the repo's build
# rule). Prints the path; returns 1 when it cannot be had — the caller then skips
# with a notice, like every other gate does for a missing tool.
resolve_pleamar_tool() {
  local name="$1" root="${2:-.}" out
  if command -v "$name" > /dev/null 2>&1; then
    command -v "$name"
    return 0
  fi
  out="$(nix build --no-link --print-out-paths "$root#$name" --option substitute false 2> /dev/null)" || return 1
  [ -x "$out/bin/$name" ] || return 1
  printf '%s\n' "$out/bin/$name"
}
