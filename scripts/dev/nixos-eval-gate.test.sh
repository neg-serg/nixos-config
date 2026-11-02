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
#      stderr) and still answers like a live eval; skipped as root;
#  11. tier B answers byte-identically through the parallel and the plain shape
#      (`builtins.parallel` is a forcing hint, so the value must not move);
#  12. no `builtins.parallel` (a NIX wrapper answers `false` to the probe): the
#      gate falls back to the plain shape, says so on --verbose, never claims the
#      fast path and still answers correctly;
#  13. the key does not move with the shape — parallelism is a forcing order, not
#      an input, so a plain-shape call hits the entry a parallel-shape call wrote;
#  14. one evaluation, many answers: `--json` returns all five fields and
#      `--field label` returns the label, both equal to live evals;
#  15. the tier-B key was rebuilt from git blob OIDs instead of whole-tree diffs
#      (v3 -> v4), so the old key is frozen at the bottom of this file as
#      `legacy_key_b` and the two are compared over a matrix of tree states:
#      clean, edited, added, deleted, mode-only change, staged-only change, type
#      change and each of their restores. For every pair of states the v3 key and
#      the v4 key must agree on *whether* the state changed — and the same-bytes
#      restore and the mode-only change are asserted on their own, because those
#      are the two ways a content hash can be weaker than the diff it replaced,
#      and so is a symlink retargeted between files with identical bytes;
#  16. a mode-only change through the real cache: MISS with a new key, the old
#      entry kept and hit again once the mode is restored (an entry is invalidated
#      exactly when it should be, no more and no less);
#  17. `--print-key` reports the same key a real run computes and stores nothing.
#
# Every tier-B value is compared against a live `nix eval` of the plain shape,
# which is the oracle for both shapes.
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
# $run_env carries per-call environment (`EVAL_GATE_PARALLEL=off`, `NIX=…`).
out="" err="" ms=0 rc=0
run_env=()
run_gate() {
  local start err_file="$TMP/stderr.$$"
  start="$(now_ms)"
  rc=0
  out="$(env ${run_env[@]+"${run_env[@]}"} bash ./scripts/dev/nixos-eval-gate.sh "$@" 2> "$err_file")" || rc=$?
  ms=$(($(now_ms) - start))
  err="$(cat "$err_file")"
}

live_label() { nix eval --raw ".#$LABEL_ATTR"; }
live_drv() { nix eval --raw ".#$DRV_ATTR"; }
# Cache entries only: the answer files are named by the key, the proof records
# carry a `.record` suffix and must not be counted as answers.
entries() {
  local n=0 f
  for f in "$EVAL_GATE_CACHE_DIR"/*; do
    case "${f##*/}" in
      *[!0-9a-f]*) : ;;
      *) n=$((n + 1)) ;;
    esac
  done
  printf '%s\n' "$n"
}
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
ck "wrote a proof record beside the answer" test -f "$EVAL_GATE_CACHE_DIR/$akey1.record"
ck "the record names the tier and the answer" contains "$(head -n 12 "$EVAL_GATE_CACHE_DIR/$akey1.record")" "answer $label"
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
ck "the record names the key format" contains "$(head -n 12 "$EVAL_GATE_CACHE_DIR/$bkey1.record")" "key_format v4"
ck "the record stores the key material itself" contains "$(grep -c -a -e 'wtfiles' "$EVAL_GATE_CACHE_DIR/$bkey1.record")" "1"
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

echo
echo "11. tier B: the parallel shape answers byte-identically to the plain shape"
run_gate --drv --no-cache --verbose
par_out="$out"
par_ms="$ms"
ck "parallel-shape exit status is 0" test "$rc" -eq 0
ck "parallel shape used the fan-out" contains "$err" "parallel shape"
ck "parallel-shape answer equals a live plain eval" test "$par_out" = "$drv1"
run_env=(EVAL_GATE_PARALLEL=off)
run_gate --drv --no-cache --verbose
plain_out="$out"
plain_ms="$ms"
run_env=()
ck "plain-shape exit status is 0" test "$rc" -eq 0
ck "plain shape says so" contains "$err" "plain shape"
ck "plain-shape answer equals a live plain eval" test "$plain_out" = "$drv1"
ck "the two shapes are byte-identical" test "$par_out" = "$plain_out"
echo "   parallel: ${par_ms} ms, plain: ${plain_ms} ms, same bytes"

echo
echo "12. no builtins.parallel: fall back to the plain shape, same answer"
# A stand-in Nix that answers `false` to the probe and forwards everything else:
# the only way to exercise the fallback on this host, where the primop is real.
cat > "$TMP/nix-no-parallel" << 'WRAP'
#!/usr/bin/env bash
for arg in "$@"; do
  if [ "$arg" = 'builtins ? parallel' ]; then
    printf 'false\n'
    exit 0
  fi
done
exec nix "$@"
WRAP
chmod +x "$TMP/nix-no-parallel"
run_env=(NIX="$TMP/nix-no-parallel")
run_gate --drv --no-cache --verbose
run_env=()
ck "exit status is 0 without the primop" test "$rc" -eq 0
ck "falls back to the plain shape" contains "$err" "plain shape"
ck "never claims the parallel shape" not_contains "$err" "parallel shape"
ck "the fallback answers like a live eval" test "$out" = "$drv1"
echo "   fallback: ${ms} ms, answer $out"
# The whole-set expression must also fall back without the primop, and a scalar
# field must stay a bare string (not JSON-quoted) so both shapes stay identical.
run_env=(NIX="$TMP/nix-no-parallel")
run_gate --drv --field label
run_env=()
ck "--field falls back without the primop" test "$out" = "$label"

echo
echo "13. parallelism is a forcing order, not an input: the key does not move"
run_gate --drv --verbose
ck "the warm tier-B entry is a hit" contains "$err" "hit"
ck "the hit key is the original tier-B key" test "$(key_of "$err")" = "$bkey1"
par_key="$(key_of "$err")"
run_env=(EVAL_GATE_PARALLEL=off)
run_gate --drv --verbose
run_env=()
ck "plain-shape exit status is 0" test "$rc" -eq 0
ck "plain shape reuses the parallel entry (same key space)" contains "$err" "hit"
ck "the key is identical in both shapes" test "$(key_of "$err")" = "$par_key"
ck "the value is identical in both shapes" test "$out" = "$drv1"

echo
echo "14. one evaluation, many answers: --json and --field"
if ! command -v jq > /dev/null 2>&1; then
  echo "   skip: jq not available, the JSON case cannot be checked"
else
  run_gate --drv --json
  json="$out"
  json_ms="$ms"
  ck "--json exit status is 0" test "$rc" -eq 0
  ck "it is a JSON object with all five fields" test "$(jq -r 'keys | length' <<< "$json")" -eq 5
  ck "drvPath field equals the tier-B answer" test "$(jq -r .drvPath <<< "$json")" = "$drv1"
  ck "label field equals a live label eval" test "$(jq -r .label <<< "$json")" = "$(live_label)"
  ck "toplevel field is a store path" contains "$(jq -r .toplevel <<< "$json")" "/nix/store/"
  ck "system field names the host platform" test "$(jq -r .system <<< "$json")" = "x86_64-linux"
  ck "one evaluation answered the whole set (${json_ms} ms)" test "$json_ms" -lt 20000
  run_gate --drv --field label
  ck "--field exit status is 0" test "$rc" -eq 0
  ck "--field label equals a live eval" test "$out" = "$label"
  echo "   --json: ${json_ms} ms for five answers, --field: ${ms} ms"
fi

echo
echo "15. old key (v3) vs new key (v4): the change/no-change matrix"
# The gate has no v3 path any more, so the key this change replaced is frozen
# here and used as an oracle: exactly the material the previous commit hashed —
# header, HEAD, `git status`, the whole `git diff HEAD --binary` and a sha256 per
# untracked file.
legacy_key_b() {
  local path sum
  {
    printf 'format\0v3\0'
    printf 'tier\0b\0'
    printf 'attr\0%s\0' "$DRV_ATTR"
    printf 'selector\0attr\0'
    printf 'nix\0%s\0' "$(nix --version)"
    printf 'root\0%s\0' "$(pwd -P)"
    printf 'head\0'
    git rev-parse HEAD
    printf '\0'
    printf 'status\0'
    git status --porcelain=v1 -z | sort -z
    printf '\0'
    printf 'diff\0'
    git diff HEAD --binary --no-color --no-ext-diff --no-textconv \
      --src-prefix=a/ --dst-prefix=b/
    printf '\0'
    printf 'untracked\0'
    while IFS= read -r -d '' path; do
      if [ -L "$path" ]; then
        sum="link:$(readlink -- "$path" || true)"
      elif [ -x "$path" ]; then
        sum="x:$(sha256sum -- "$path" || true)"
      else
        sum="-:$(sha256sum -- "$path" || true)"
      fi
      printf '%s\0%s\0' "$path" "$sum"
    done < <(git ls-files --others --exclude-standard -z)
    printf '\0'
    printf 'end\0'
  } | sha256sum | cut -d' ' -f1
}

# One row of the matrix: the state's name plus the key each of the two
# implementations gives it.
declare -a st_name=() st_old=() st_new=()
declare -A st_index=()
matrix_state() {
  st_name+=("$1")
  st_index["$1"]=$((${#st_name[@]} - 1))
  st_old+=("$(legacy_key_b)")
  st_new+=("$(bash ./scripts/dev/nixos-eval-gate.sh --drv --print-key)")
}

MATRIX_MODE_FILE="$NIXFILE"
mode_base="$(stat -c %a "$CLONE/$MATRIX_MODE_FILE")"
cp -p "$CLONE/$ASSET" "$TMP/matrix-asset.orig"

matrix_state "clean"
printf '\n# matrix: edited\n' >> "$CLONE/$ASSET"
matrix_state "one file edited"
cp -p "$TMP/matrix-asset.orig" "$CLONE/$ASSET"
matrix_state "same bytes restored"
printf 'matrix\n' > "$CLONE/matrix-untracked.txt"
matrix_state "one file added"
rm -f "$CLONE/matrix-untracked.txt"
matrix_state "added file removed"
rm -f "$CLONE/$ASSET"
matrix_state "one file deleted"
cp -p "$TMP/matrix-asset.orig" "$CLONE/$ASSET"
matrix_state "deleted file restored"
if [ -x "$CLONE/$MATRIX_MODE_FILE" ]; then
  chmod -x "$CLONE/$MATRIX_MODE_FILE"
else
  chmod +x "$CLONE/$MATRIX_MODE_FILE"
fi
matrix_state "mode-only change"
chmod "$mode_base" "$CLONE/$MATRIX_MODE_FILE"
matrix_state "mode reverted"
printf '\n# matrix: staged\n' >> "$CLONE/$ASSET"
git -C "$CLONE" add -- "$ASSET"
matrix_state "staged-only change"
git -C "$CLONE" reset -q -- "$ASSET"
cp -p "$TMP/matrix-asset.orig" "$CLONE/$ASSET"
matrix_state "staged change reverted"
rm -f "$CLONE/$ASSET"
ln -s ../../../../README.md "$CLONE/$ASSET"
matrix_state "type change (file -> symlink)"
rm -f "$CLONE/$ASSET"
cp -p "$TMP/matrix-asset.orig" "$CLONE/$ASSET"
matrix_state "type change reverted"
# An untracked symlink retargeted between two files with identical bytes: the
# blob OID of the target content cannot see this, so the link target has to be a
# field of its own (it was a `link:` line in the v3 key, it is `wtlinks` in v4).
printf 'same bytes\n' > "$CLONE/matrix-a.txt"
printf 'same bytes\n' > "$CLONE/matrix-b.txt"
ln -s matrix-a.txt "$CLONE/matrix-link"
matrix_state "untracked symlink"
rm -f "$CLONE/matrix-link"
ln -s matrix-b.txt "$CLONE/matrix-link"
matrix_state "symlink retargeted, same bytes"
rm -f "$CLONE/matrix-link" "$CLONE/matrix-a.txt" "$CLONE/matrix-b.txt"
matrix_state "symlink removed"

# Both implementations against the base state, side by side: "changed" means the
# key differs from the clean row, and the last column is the agreement itself.
echo "   state                       v3 key      v4 key      agree"
printf '   %-27s %-11s %-11s %s\n' "clean" "${st_old[0]:0:10}" "${st_new[0]:0:10}" "-"
table_disagreements=""
pairs=0
for i in "${!st_name[@]}"; do
  if [ "$i" -eq 0 ]; then
    continue
  fi
  o="changed"
  n="changed"
  if [ "${st_old[$i]}" = "${st_old[0]}" ]; then o="same"; fi
  if [ "${st_new[$i]}" = "${st_new[0]}" ]; then n="same"; fi
  agree="yes"
  if [ "$o" != "$n" ]; then
    agree="NO"
    table_disagreements+="${st_name[$i]}; "
  fi
  printf '   %-27s %-11s %-11s %s\n' "${st_name[$i]}" "$o" "$n" "$agree"
done
# Every pair of states, not just each state against the base: two different
# dirty states must not collide in one key and be the same in the other.
for i in "${!st_name[@]}"; do
  for j in "${!st_name[@]}"; do
    if [ "$j" -le "$i" ]; then
      continue
    fi
    pairs=$((pairs + 1))
    o_same=0
    n_same=0
    if [ "${st_old[$i]}" = "${st_old[$j]}" ]; then o_same=1; fi
    if [ "${st_new[$i]}" = "${st_new[$j]}" ]; then n_same=1; fi
    if [ "$o_same" -ne "$n_same" ]; then
      table_disagreements+="${st_name[$i]} vs ${st_name[$j]}; "
    fi
  done
done
echo "   ${#st_name[@]} states, $pairs pairs, disagreements: ${table_disagreements:-none}"

# changed_in_both / same_in_both: what "agreement" means per named state, with
# the base state as the reference.
changed_in_both() {
  local i="${st_index[$1]}"
  [ "${st_old[$i]}" != "${st_old[0]}" ] && [ "${st_new[$i]}" != "${st_new[0]}" ]
}
same_in_both() {
  local i="${st_index[$1]}"
  [ "${st_old[$i]}" = "${st_old[0]}" ] && [ "${st_new[$i]}" = "${st_new[0]}" ]
}

ck "the v4 key is never empty" test -n "${st_new[0]}"
ck "both keys move when a tracked file is edited" changed_in_both "one file edited"
ck "both keys move when a file is added" changed_in_both "one file added"
ck "both keys move when a file is deleted" changed_in_both "one file deleted"
ck "both keys move on a mode-only change" changed_in_both "mode-only change"
ck "both keys move on a staged-only change" changed_in_both "staged-only change"
ck "both keys move on a type change" changed_in_both "type change (file -> symlink)"
changed_between() {
  local i="${st_index[$1]}" j="${st_index[$2]}"
  [ "${st_old[$i]}" != "${st_old[$j]}" ] && [ "${st_new[$i]}" != "${st_new[$j]}" ]
}
ck "both keys move when an untracked symlink is retargeted to a file with identical bytes" \
  changed_between "untracked symlink" "symlink retargeted, same bytes"
ck "a same-bytes restore returns both keys to the base value" same_in_both "same bytes restored"
restores=("added file removed" "deleted file restored" "mode reverted" "staged change reverted" "type change reverted" "symlink removed")
bad_restores=""
for restore_state in "${restores[@]}"; do
  if ! same_in_both "$restore_state"; then
    bad_restores+="$restore_state; "
  fi
done
ck "every other restore returns both keys to the base value (${bad_restores:-all})" test -z "$bad_restores"
ck "the two keys agree on change/no-change for all $pairs pairs" test -z "$table_disagreements"

echo
echo "16. a mode-only change through the real cache: one new entry, old one kept"
before="$(entries)"
mode_nix="$(stat -c %a "$CLONE/$NIXFILE")"
if [ -x "$CLONE/$NIXFILE" ]; then
  chmod -x "$CLONE/$NIXFILE"
else
  chmod +x "$CLONE/$NIXFILE"
fi
run_gate --drv --verbose
mkey="$(key_of "$err")"
ck "the mode-only change is a miss" contains "$err" "miss"
ck "the mode-only change moved the key" test "$mkey" != "$bkey1"
ck "exactly one entry was added" test "$(entries)" -eq $((before + 1))
ck "the entry for the unmodified tree is still there" test -f "$EVAL_GATE_CACHE_DIR/$bkey1"
chmod "$mode_nix" "$CLONE/$NIXFILE"
run_gate --drv --verbose
ck "restoring the mode hits the original entry again" contains "$err" "hit"
ck "with the original key" test "$(key_of "$err")" = "$bkey1"
ck "and the original drvPath" test "$out" = "$drv1"

echo
echo "17. --print-key: the key a real run computed, and nothing stored"
before="$(entries)"
run_gate --drv --print-key
ck "--print-key exit status is 0" test "$rc" -eq 0
ck "--print-key agrees with the key a real run used" test "$out" = "$bkey1"
ck "--print-key stored nothing" test "$(entries)" -eq "$before"

summary "nixos-eval-gate self-test"
