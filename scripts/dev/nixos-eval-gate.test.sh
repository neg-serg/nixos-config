#!/usr/bin/env bash
# Self-test for scripts/dev/nixos-eval-gate.sh: prove both tiers are honest.
#
# Tier A (default, `config.system.nixos.label`) is keyed on the evaluation input
# set, so the interesting claim is two-sided: an asset edit must HIT, a Nix edit
# must MISS, and every hit must equal a live eval. Tier B (`--drv`) is keyed on
# the whole tree because the toplevel embeds the flake source, so the same asset
# edit must MISS — and the value must really have changed, or the miss would be
# pointless. In order:
#   1. tier A cold: miss, real eval, value equals `nix eval` of the label;
#   2. tier A warm: hit, identical value, under 2 s;
#   3. tier B cold: miss, value equals `nix eval` of the drvPath;
#   4. tier B warm: hit, identical value, under 2 s;
#   5. edit files/pleamar/shells/bar/bar.plm (not an eval input):
#      tier A HIT with the same label (a live eval confirms it), tier B MISS with
#      a different drvPath (a live eval confirms the new one) — the evidence that
#      tier B may not be keyed on the input set;
#   6. restore the scene: tier B hits the original drvPath again;
#   7. edit modules/security/default.nix (an eval input): tier A MISS, new key,
#      recomputed label equals a live eval;
#   8. restore it: tier A hits the original key again;
#   9. --no-cache: live eval, same value, nothing stored;
#  10. an unreadable untracked `.nix` file: tier A refuses to cache (notice on
#      stderr) and still answers like a live eval; skipped as root.
#
# Hermetic: everything runs in a `git clone --shared` of this repo under $TMPDIR,
# so the real tree is only read, the cache is steered into the same temp dir with
# EVAL_GATE_CACHE_DIR, and the clone is removed on exit.
#
# Usage: bash scripts/dev/nixos-eval-gate.test.sh
# Exit status: 0 when every assertion passes.

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

# lib.sh's check() runs "$@" bare, so `set -e` would kill the run on the first
# failing assertion and hide the rest; this wrapper keeps every result.
ck() {
  local label="$1" st=0
  shift
  "$@" || st=$?
  assert "$st" "$label"
}

SRC_REPO="$(repo_root)"
GATE="$SRC_REPO/scripts/dev/nixos-eval-gate.sh"
LABEL_ATTR="nixosConfigurations.trantor.config.system.nixos.label"
DRV_ATTR="nixosConfigurations.trantor.config.system.build.toplevel.drvPath"
ASSET="files/pleamar/shells/bar/bar.plm"
NIXFILE="modules/security/default.nix"

TMP="$(mktemp -d "${TMPDIR:-/tmp}/nixos-eval-gate-test.XXXXXXXX")"
cleanup() {
  # Only ever the mktemp dir this test created.
  case "$TMP" in
    "${TMPDIR:-/tmp}"/nixos-eval-gate-test.*) rm -rf -- "$TMP" ;;
  esac
}
trap cleanup EXIT

# Milliseconds from the bash clock, so the timing assertions need no `date` fork.
now_ms() {
  local us="${EPOCHREALTIME/./}"
  printf '%s' "$((us / 1000))"
}

# nix needs a writable XDG_CACHE_HOME for its fetcher locks; the agent sandbox has
# $HOME read-only, so fall back to the repo-local scratch cache exactly like the
# `just update` recipe does. The gate's own cache is pinned separately, below.
nix_cache="${XDG_CACHE_HOME:-$HOME/.cache}"
if (mkdir -p "$nix_cache/nix" && touch "$nix_cache/nix/.probe") 2> /dev/null; then
  rm -f "$nix_cache/nix/.probe"
else
  nix_cache="$SRC_REPO/.agent/tmp-nix-cache"
  echo "note: $HOME cache not writable, using $nix_cache for nix itself"
fi
export XDG_CACHE_HOME="$nix_cache"
export EVAL_GATE_CACHE_DIR="$TMP/gate-cache"

echo "self-test: cloning $SRC_REPO into $TMP/repo"

git clone --shared --quiet "$SRC_REPO" "$TMP/repo"
# The gate is new in the working tree, so a clone of HEAD does not carry it. Copy
# it in: it stays untracked, which also exercises the untracked-input key path.
install -m 0755 "$GATE" "$TMP/repo/scripts/dev/nixos-eval-gate.sh"
CLONE="$TMP/repo"
cd "$CLONE"

# One gate invocation: stdout in $out, stderr in $err, wall time in $ms, status in $rc.
out="" err="" ms=0 rc=0
run_gate() {
  local start err_file="$TMP/stderr.$$"
  start="$(now_ms)"
  rc=0
  out="$(bash ./scripts/dev/nixos-eval-gate.sh "$@" 2> "$err_file")" || rc=$?
  ms=$(($(now_ms) - start))
  err="$(cat "$err_file")"
}

live_label() { nix eval --raw ".#$LABEL_ATTR"; }
live_drv() { nix eval --raw ".#$DRV_ATTR"; }
entries() { ls -1 "$EVAL_GATE_CACHE_DIR" 2> /dev/null | wc -l | tr -d ' '; }
key_of() { sed -n 's/.* key=\([0-9a-f]\{64\}\).*/\1/p' <<< "$1" | tail -n 1; }

echo
echo "1. tier A cold: miss, real eval, value equals a live eval"
run_gate --verbose
label="$out"
akey1="$(key_of "$err")"
echo "   cold: ${ms} ms, key ${akey1:0:12}..."
ck "exit status is 0" test "$rc" -eq 0
ck "reports a miss" contains "$err" "miss"
ck "logged a key" test -n "$akey1"
ck "printed the label" test -n "$label"
ck "exactly one cache entry" test "$(entries)" -eq 1
ck "label equals a live eval" test "$label" = "$(live_label)"
echo "   label: $label"

echo
echo "2. tier A warm: hit, identical value, under 2 s"
run_gate --verbose
ck "exit status is 0" test "$rc" -eq 0
ck "reports a hit" contains "$err" "hit"
ck "identical value" test "$out" = "$label"
ck "same key as the cold call" test "$(key_of "$err")" = "$akey1"
ck "hit under 2 s (${ms} ms)" test "$ms" -lt 2000
echo "   hit: ${ms} ms"

echo
echo "3. tier B cold: miss, drvPath equals a live eval"
run_gate --drv --verbose
drv1="$out"
bkey1="$(key_of "$err")"
echo "   cold: ${ms} ms, key ${bkey1:0:12}..."
ck "exit status is 0" test "$rc" -eq 0
ck "reports a miss" contains "$err" "miss"
ck "printed a store path" contains "$drv1" "/nix/store/"
ck "drvPath equals a live eval" test "$drv1" = "$(live_drv)"
echo "   drvPath: $drv1"

echo
echo "4. tier B warm: hit, identical value, under 2 s"
run_gate --drv --verbose
ck "exit status is 0" test "$rc" -eq 0
ck "reports a hit" contains "$err" "hit"
ck "identical value" test "$out" = "$drv1"
ck "same key as the cold call" test "$(key_of "$err")" = "$bkey1"
ck "hit under 2 s (${ms} ms)" test "$ms" -lt 2000
echo "   hit: ${ms} ms"

echo
echo "5. edit an asset ($ASSET): tier A hits, tier B misses"
cp "$CLONE/$ASSET" "$TMP/asset.orig"
printf '\n# eval-gate self-test\n' >> "$ASSET"
run_gate --verbose
ck "tier A exit status is 0" test "$rc" -eq 0
ck "tier A reports a hit" contains "$err" "hit"
ck "tier A kept the same key" test "$(key_of "$err")" = "$akey1"
ck "tier A served the same label" test "$out" = "$label"
ck "the label really is unchanged (live eval)" test "$(live_label)" = "$label"
echo "   tier A hit after an asset edit: ${ms} ms"
run_gate --drv --verbose
drv2="$out"
ck "tier B exit status is 0" test "$rc" -eq 0
ck "tier B reports a miss" contains "$err" "miss"
ck "tier B recomputed a different drvPath" test "$drv2" != "$drv1"
ck "tier B matches a live eval" test "$drv2" = "$(live_drv)"
echo "   tier B miss, new drvPath: $drv2"

echo
echo "6. restore the asset: tier B hits the original drvPath again"
cp "$TMP/asset.orig" "$CLONE/$ASSET"
run_gate --drv --verbose
ck "exit status is 0" test "$rc" -eq 0
ck "reports a hit" contains "$err" "hit"
ck "same key as the first tier B call" test "$(key_of "$err")" = "$bkey1"
ck "prints the original drvPath" test "$out" = "$drv1"

echo
echo "7. edit a Nix input ($NIXFILE): tier A misses and reevaluates"
cp "$CLONE/$NIXFILE" "$TMP/nix.orig"
printf '\n# eval-gate self-test scratch comment\n' >> "$NIXFILE"
run_gate --verbose
akey2="$(key_of "$err")"
ck "exit status is 0" test "$rc" -eq 0
ck "reports a miss" contains "$err" "miss"
ck "key changed with the Nix edit" test "$akey2" != "$akey1"
ck "label equals a live eval" test "$out" = "$(live_label)"
echo "   key moved: ${akey1:0:12}... -> ${akey2:0:12}..."

echo
echo "8. restore the Nix file: tier A hits the original key again"
cp "$TMP/nix.orig" "$CLONE/$NIXFILE"
run_gate --verbose
ck "exit status is 0" test "$rc" -eq 0
ck "reports a hit" contains "$err" "hit"
ck "same key as the first tier A call" test "$(key_of "$err")" = "$akey1"
ck "prints the original label" test "$out" = "$label"

echo
echo "9. --no-cache: live eval, same value, nothing stored"
before="$(entries)"
run_gate --no-cache
ck "exit status is 0" test "$rc" -eq 0
ck "prints the identical label" test "$out" = "$label"
ck "no entry was added" test "$(entries)" -eq "$before"

echo
echo "10. unreadable untracked Nix input: refuse to cache, still answer correctly"
if [ "$(id -u)" -eq 0 ]; then
  echo "   skip: root can read anything, the refusal cannot be provoked"
else
  : > "$CLONE/scratch-input.nix"
  chmod 000 "$CLONE/scratch-input.nix"
  run_gate
  ck "exit status is 0" test "$rc" -eq 0
  ck "says it cannot hash the input set" contains "$err" "cannot hash"
  ck "says it caches nothing" contains "$err" "caching nothing"
  ck "answer still equals a live eval" test "$out" = "$(live_label)"
  chmod 600 "$CLONE/scratch-input.nix"
  rm -f "$CLONE/scratch-input.nix"
fi

summary "nixos-eval-gate self-test"
