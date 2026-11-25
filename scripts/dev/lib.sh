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

# ── parallel map ────────────────────────────────────────────────────────────
# pmap [-j JOBS] [-0] -- FUNCTION
#
# Read items from stdin (one per line; -0 for NUL-separated names) and run
# `FUNCTION ITEM` once per item in a subshell, at most JOBS at a time. Every
# call's stdout+stderr is captured and replayed in input order, so the output
# is exactly what the serial `for item in ...` loop printed — same lines, same
# order — while the work runs concurrently.
#
# A failing item does not stop the others: all of them run. Afterwards
# $pmap_ok / $pmap_failed hold the counts and the return status is 1 when at
# least one item failed. pmap only replays the captured diagnostics; deciding
# what a failure means stays with the caller.
#
# JOBS defaults to $PMAP_JOBS, then to nproc. The bound is a hard one: these
# checkers spawn compilers, and oversubscribing the box makes the whole suite
# slower, not faster.
#
# The item's exit status travels through a file rather than `wait`, because
# the concurrency throttle reaps jobs with `wait -n`: a reaped pid can no
# longer be waited on, but its status file is still there.
#
# The replay below reads that file and the item's log with builtins only. It
# used to shell out to `cat` (twice) and `tail` per item, and that serial
# harness cost dwarfed the checkers it fanned out: 411 items spent 0.48 s in
# pmap alone, against 0.35 s of actual checking. `read`/`mapfile` are the same
# bytes for a text log, at ~0.1 ms per item.
pmap() {
  local jobs="${PMAP_JOBS:-}" null=0 func item tmp
  local -a items=()
  local -a pids=()
  local i n running=0 rc
  local -a chunk=()

  while [ $# -gt 0 ]; do
    case "$1" in
      -j | --jobs)
        jobs="${2:?pmap: -j needs a value}"
        shift 2
        ;;
      -0 | --null)
        null=1
        shift
        ;;
      --)
        shift
        break
        ;;
      *)
        break
        ;;
    esac
  done
  func="${1:-}"
  if [ -z "$func" ]; then
    echo "pmap: missing FUNCTION" >&2
    return 2
  fi

  if [ "$null" -eq 1 ]; then
    while IFS= read -r -d '' item; do items+=("$item"); done
  else
    # `|| [ -n "$item" ]` keeps a last line that has no trailing newline.
    while IFS= read -r item || [ -n "$item" ]; do items+=("$item"); done
  fi

  pmap_ok=0
  pmap_failed=0
  n=${#items[@]}
  if [ "$n" -eq 0 ]; then
    return 0
  fi
  # An empty or bogus JOBS falls through to the machine's core count.
  if ! [ "$jobs" -ge 1 ] 2> /dev/null; then
    jobs=$(nproc 2> /dev/null || echo 4)
  fi

  tmp=$(mktemp -d "${TMPDIR:-/tmp}/pmap.XXXXXXXX") || return 1
  for ((i = 0; i < n; i++)); do
    (
      rc=0
      "$func" "${items[$i]}" || rc=$?
      printf '%s\n' "$rc" > "$tmp/$i.rc"
    ) > "$tmp/$i.log" 2>&1 &
    pids[i]=$!
    running=$((running + 1))
    if [ "$running" -ge "$jobs" ]; then
      wait -n || true
      running=$((running - 1))
    fi
  done

  for ((i = 0; i < n; i++)); do
    wait "${pids[$i]}" 2> /dev/null || true
    if [ -s "$tmp/$i.log" ]; then
      # `-d ''` has no NUL to split on, so the whole log lands in one element
      # and is replayed verbatim, trailing newlines included.
      chunk=()
      mapfile -d '' -t chunk < "$tmp/$i.log"
      printf '%s' "${chunk[@]}"
      # A worker that stopped mid-line must not glue the next block onto it.
      [ "${chunk[${#chunk[@]} - 1]: -1}" = $'\n' ] || printf '\n'
    fi
    rc=1
    read -r rc < "$tmp/$i.rc" 2> /dev/null || rc=1
    if [ "$rc" -eq 0 ]; then
      pmap_ok=$((pmap_ok + 1))
    else
      pmap_failed=$((pmap_failed + 1))
    fi
  done
  rm -rf "$tmp"

  [ "$pmap_failed" -eq 0 ]
}
