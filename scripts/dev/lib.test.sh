#!/usr/bin/env bash
# shellcheck disable=SC2154  # pmap_ok/pmap_failed are set by pmap in lib.sh
# Self-test for scripts/dev/lib.sh — pmap only, the helper the gates fan out
# with. Not wired into `lint` (it tests the harness, not the repo); run it
# after touching pmap:
#
#   bash scripts/dev/lib.test.sh
#
# What it proves, and why each case exists:
#   1. output is replayed in input order even when the items finish in a
#      different order — the gates' reports are read top-to-bottom;
#   2. a failing item does not abort the batch, the counts are exact, and the
#      return status is 1;
#   3. the -j bound is honoured (no more than JOBS items overlap) while the
#      work really happens concurrently (more than one item overlaps);
#   4. NUL-separated input survives names with spaces, which is why the gates
#      feed file lists with -0;
#   5. an empty list is a clean no-op, not a failed batch.
#
# No `set -e` on purpose: case 2 runs a batch that fails, and the test has to
# read that status instead of dying on it.
set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ck DESC COMMAND...: assert that a command succeeded. The output is shown on
# failure only, so a green run stays short.
ck() {
  local desc=$1
  shift
  if "$@" > "$TMP/ck.out" 2>&1; then
    assert 0 "$desc"
  else
    assert 1 "$desc"
    sed 's/^/       /' "$TMP/ck.out"
  fi
}

echo "1. replay keeps input order, not completion order"
# Descending sleeps: replaying as jobs finish would print 4 3 2 1.
order_one() {
  sleep "0.0$((5 - $1))"
  echo "item $1"
}
pmap -j 4 -- order_one < <(printf '%s\n' 1 2 3 4) > "$TMP/order.out"
mapfile -t got < "$TMP/order.out"
want=("item 1" "item 2" "item 3" "item 4")
ck "order is 1 2 3 4" [ "${got[*]}" = "${want[*]}" ]
ck "4 ok, 0 failed" [ "$pmap_ok" -eq 4 -a "$pmap_failed" -eq 0 ]

echo "2. a failing item does not stop the batch"
sometimes_fail() {
  echo "ran $1"
  # 2 and 4 fail; 1 and 3 must still run.
  case "$1" in 2 | 4) return 1 ;; *) return 0 ;; esac
}
pmap -j 2 -- sometimes_fail < <(printf '%s\n' 1 2 3 4) > "$TMP/fail.out"
rc=$?
mapfile -t got < "$TMP/fail.out"
ck "status is non-zero" [ "$rc" -ne 0 ]
ck "all four items ran" [ "${#got[@]}" -eq 4 ]
ck "2 ok" [ "$pmap_ok" -eq 2 ]
ck "2 failed" [ "$pmap_failed" -eq 2 ]

echo "3. -j bounds concurrency and still overlaps"
# Every item logs start/end; nesting is read from the interleaving. Six items
# sleeping 0.15 s with -j 2: nesting 2 is the design, 6 means the bound is
# ignored, 1 means it ran serially.
log="$TMP/nesting"
overlap_one() {
  echo start >> "$log"
  sleep 0.15
  echo end >> "$log"
}
pmap -j 2 -- overlap_one < <(printf '%s\n' 1 2 3 4 5 6) > /dev/null
mapfile -t lines < "$log"
max=0
cur=0
for line in "${lines[@]}"; do
  if [ "$line" = start ]; then
    cur=$((cur + 1))
    [ "$cur" -gt "$max" ] && max=$cur
  else
    cur=$((cur - 1))
  fi
done
ck "never more than 2 in flight (saw $max)" [ "$max" -le 2 ]
ck "at least 2 in flight (saw $max)" [ "$max" -ge 2 ]

echo "4. NUL-separated input keeps names with spaces"
names="$TMP/a b.txt"
: > "$names"
show_one() { printf '[%s]' "$1"; }
out="$(pmap -0 -j 2 -- show_one < <(printf '%s\0' "$names"))"
ck "space in path survived" [ "$out" = "[$names]" ]

echo "5. an empty item list is a clean no-op"
pmap -j 2 -- show_one < <(printf '') > /dev/null
ck "empty input returns 0" [ "$?" -eq 0 ]
ck "counts stay 0" [ "$pmap_ok" -eq 0 -a "$pmap_failed" -eq 0 ]

summary "pmap self-test"
