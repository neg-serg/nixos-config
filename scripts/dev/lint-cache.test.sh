#!/usr/bin/env bash
# Self-test for the shellcheck result cache in scripts/dev/lint.sh. Not wired
# into `lint` (it tests the harness, not the repo); run after touching the
# cache:
#
#   bash scripts/dev/lint-cache.test.sh
#
# Every case runs `lint.sh` against a scratch git repo, so the real tree is
# never mutated and the cache under test is a temp directory. What it proves,
# and why each case exists:
#   1. a cold run stores an entry and the next run replays it — the marker says
#      "cached" and the replayed diagnostics are the same bytes;
#   2. editing a shell script misses, reverting the edit hits the old entry —
#      the key really follows content;
#   3. editing a file outside the hashed set (a .nix here) keeps the hit — that
#      is the point of keying on the script set instead of the whole tree;
#   4. a source line that could resolve outside the hashed set disables the
#      cache — the gate must not claim a verdict it did not verify;
#   5. a failing run is cached with its status, and the replay keeps both the
#      diagnostics and the non-zero status — a cached failure is not a green;
#   6. LINT_NO_CACHE=1 neither reads nor writes.
#
# No `set -e`: case 5 runs a gate that is meant to fail, and the test reads
# that status instead of dying on it.
set -uo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

REPO="$(repo_root)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lint-cache.XXXXXXXX")"
trap 'rm -rf "$WORK"' EXIT

SCRATCH="$WORK/tree"
CACHE="$WORK/cache"
CACHE_DIR="$CACHE/just-lint/shellcheck"
mkdir -p "$SCRATCH" "$CACHE"
cd "$SCRATCH" || exit 1

commit() { git -c user.email=t@t -c user.name=t commit -qm "$1"; }
git init -q .
printf '#!/usr/bin/env bash\necho ok\n' > good.sh
printf '#!/usr/bin/env bash\n# a target too\n' > other.bash
printf '{ }\n' > flake.nix
git add -A
commit init

# run_gate [ENV…]: run the suite against the scratch repo into $WORK/out.
# Only the shellcheck gate matters here; the other gates fail on a scratch tree
# (their scripts live in the real repo), which the test ignores.
run_gate() {
  env "$@" XDG_CACHE_HOME="$CACHE" LINT_JOBS=4 \
    bash "$REPO/scripts/dev/lint.sh" "$SCRATCH" > "$WORK/out" 2>&1
}

# ck DESC COMMAND...: assert that a command succeeded.
ck() {
  local desc=$1
  shift
  if "$@" > "$WORK/ck.out" 2>&1; then
    assert 0 "$desc"
  else
    assert 1 "$desc"
    sed 's/^/       /' "$WORK/ck.out"
  fi
}

hit() { grep -q '(cached)' "$WORK/out"; }
miss() { ! grep -q '(cached)' "$WORK/out"; }
has() { grep -q -- "$1" "$WORK/out"; }
entry_count() {
  local -a entries=("$CACHE_DIR"/*.log)
  if [ -e "${entries[0]:-}" ]; then echo "${#entries[@]}"; else echo 0; fi
}
count_is() { [ "$(entry_count)" -eq "$1" ]; }
failure_cached() {
  local -a entries=("$CACHE_DIR"/*-1.log)
  [ -e "${entries[0]:-}" ]
}
# The gate's body without its header line (which differs on a hit): the
# replay must be byte-identical to a fresh run's diagnostics.
section_body() {
  awk '/^>>> shellcheck/{f=1;next} f&&/^>>> /{exit} f' "$WORK/out" \
    | grep -v '^shellcheck: '
}
same_body() { cmp -s "$WORK/fresh" "$WORK/cached"; }
save_body() { section_body > "$WORK/fresh"; }
save_replay() { section_body > "$WORK/cached"; }

echo "1. a cold run stores an entry, the next run replays it"
run_gate
ck "one entry after the cold run" count_is 1
run_gate
ck "second run reports a cache hit" hit
ck "still one entry" count_is 1

echo "2. editing a shell script misses; reverting hits the old entry"
printf '#!/usr/bin/env bash\necho changed\n' > good.sh
run_gate
ck "edited script misses the cache" miss
ck "a second entry appeared" count_is 2
printf '#!/usr/bin/env bash\necho ok\n' > good.sh
run_gate
ck "reverted script hits its first entry" hit

echo "3. editing a non-shell file keeps the hit"
printf '{ a = 1; }\n' > flake.nix
run_gate
ck "non-shell edit still hits" hit

echo "4. an unresolvable source target disables the cache"
printf '. ./helpers\nexport X=1\n' > sourced.sh
git add sourced.sh
commit sourced
run_gate
ck "literal non-.sh source: no cache" miss
ck "and nothing new was stored" count_is 2

echo "4b. a directive naming a non-.sh target also disables the cache"
printf '# shellcheck source=helpers disable=SC1091\n. ./lib.sh\n' > sourced.sh
printf '#!/usr/bin/env bash\ntrue\n' > helpers
git add sourced.sh helpers
commit directive
run_gate
ck "source=helpers: no cache" miss
ck "and nothing new was stored" count_is 2

echo "4c. a directive naming a .sh target keeps the cache"
printf '# shellcheck source-path=SCRIPTDIR source=lib.sh disable=SC1091\n. ./lib.sh\n' > sourced.sh
printf '#!/usr/bin/env bash\ntrue\n' > lib.sh
git add sourced.sh lib.sh
commit directive-ok
run_gate
ck "source=lib.sh: first run is a miss" miss
run_gate
ck "source=lib.sh: second run hits" hit

echo "5. a failing run is cached with its status and its diagnostics"
git rm -q sourced.sh lib.sh helpers
printf '#!/usr/bin/env bash\nfor f in $(ls /tmp); do echo "$f"; done\n' > bad.sh
git add bad.sh
commit bad
run_gate
ck "first run is not cached" miss
ck "SC2045 was reported" has SC2045
save_body
run_gate
ck "replay is cached" hit
save_replay
ck "cached body is byte-identical" same_body
ck "a failed run was stored as such" failure_cached

echo "6. LINT_NO_CACHE=1 neither reads nor writes"
before=$(entry_count)
run_gate
ck "cached while enabled" hit
run_gate LINT_NO_CACHE=1
ck "disabled: no cache marker" miss
ck "disabled: entry count unchanged" count_is "$before"

echo
summary "lint-cache"
