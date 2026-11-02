#!/usr/bin/env bash
# Smoke matrix for the nix-eval-patched candidate (see ./default.nix).
#
# Run AFTER the package is built:
#   nix build /etc/nixos#nix-eval-patched --out-link /tmp/nixpatch-result
#   packages/nix-eval-patched/smoke.sh [/tmp/nixpatch-result]
#
# Every command uses XDG_CACHE_HOME=/tmp/nixpatch-cache (shared with the system
# Nix, so both binaries resolve the same flake inputs and hit the same eval
# cache) and talks to the running nix-daemon — the point is to catch a patched
# binary that "works" locally but misbehaves on the paths the patches touch
# (IsValidPath, AddTempRoot, derivation writing, toFile, cached git HEAD).
#
# Exit status: 0 when every mandatory check passes. The `/etc/nixos as-is`
# check is a parity check (patched vs system Nix on the very same dirty tree):
# on a tree with an untracked-but-referenced path both are expected to refuse,
# and the refusal is reported instead of counted as a failure — stock Nix has
# no lazy-trees, and that is the documented caveat, not a bug to fix here.
set -uo pipefail

RESULT="${1:-/tmp/nixpatch-result}"
BIN="$RESULT/bin/nix"
SYS_NIX=/run/current-system/sw/bin/nix
PIN="${NIXPKGS_SRC:-/nix/store/cm5m4hjjh37s6z82rwa0vhkbcga3m8bq-source}" # repo flake.lock pin
SNAP=/tmp/flake-snap
export XDG_CACHE_HOME=/tmp/nixpatch-cache
mkdir -p "$XDG_CACHE_HOME"

fails=0
pass() { printf 'PASS  %-32s %s\n' "$1" "$2"; }
fail() {
  printf 'FAIL  %-32s %s\n' "$1" "$2"
  fails=$((fails + 1))
}
note() { printf 'NOTE  %-32s %s\n' "$1" "$2"; }

run() { # run <name> <expected-exit> <cmd...>; OUT = stdout only, ERR = stderr tail
  local name="$1" want="$2"
  shift 2
  local rc
  OUT="$("$@" 2> /tmp/nixpatch-last.err)"
  rc=$?
  ERR="$(tail -3 /tmp/nixpatch-last.err)"
  if [ "$rc" -eq "$want" ]; then
    pass "$name" "rc=0 ${OUT:-$(printf '%s' "$ERR" | tail -1)}"
  else
    fail "$name" "rc=$rc want=$want: $(printf '%s' "$ERR" | tr '\n' ' ')"
  fi
}

echo "=== nix-eval-patched smoke matrix ($(date -Is)) ==="
printf 'binary : %s\n' "$BIN"
printf 'system : %s (%s)\n\n' "$SYS_NIX" "$("$SYS_NIX" --version)"

# 1. identity of the artifact
run "--version" 0 "$BIN" --version

# 2. eval sanity. The literal `--raw --expr '1 + 1'` is an eval error in *any*
#    Nix (`--raw` needs a string), so it is asserted as parity with the system
#    binary; the arithmetic itself is checked with plain `eval` and with a
#    `toString` form that --raw can print.
lit_patched="$("$BIN" eval --raw --expr '1 + 1' 2>&1 | tail -1)"
lit_system="$("$SYS_NIX" eval --raw --expr '1 + 1' 2>&1 | tail -1)"
if [ "$lit_patched" = "$lit_system" ]; then
  pass "eval --raw --expr '1 + 1'" "same as system Nix: ${lit_patched}"
else
  fail "eval --raw --expr '1 + 1'" "patched='${lit_patched}' system='${lit_system}'"
fi
run "eval --expr '1 + 1'" 0 "$BIN" eval --expr '1 + 1'
[ "${OUT:-}" = "2" ] && pass "1 + 1 == 2" "yes" || fail "1 + 1 == 2" "got '${OUT:-}'"
run "eval --raw toString (1 + 1)" 0 "$BIN" eval --raw --expr 'toString (1 + 1)'
[ "${OUT:-}" = "2" ] && pass "toString (1 + 1) == 2" "yes" || fail "toString (1 + 1) == 2" "got '${OUT:-}'"

# 3./4. store + daemon round trip and a real build, through the flake registry
# (nixpkgs) and through the repo's own pin.
run "eval nixpkgs#hello.name" 0 "$BIN" eval --raw 'nixpkgs#hello.name'
run "eval pinned nixpkgs#hello.name" 0 "$BIN" eval --raw "$PIN#hello.name"
run "build --no-link nixpkgs#hello" 0 "$BIN" build --no-link 'nixpkgs#hello'

# 5. clean snapshot of this repo: both binaries must produce the same toplevel.
rm -rf "$SNAP"
mkdir -p "$SNAP"
git -C /etc/nixos archive HEAD | tar -x -C "$SNAP"
printf '\nsnapshot: HEAD %s -> %s\n' "$(git -C /etc/nixos rev-parse HEAD)" "$SNAP"
drv_patched="$("$BIN" eval --raw "$SNAP#nixosConfigurations.trantor.config.system.build.toplevel.drvPath" 2> /dev/null)"
rc_p=$?
drv_system="$("$SYS_NIX" eval --raw "$SNAP#nixosConfigurations.trantor.config.system.build.toplevel.drvPath" 2> /dev/null)"
rc_s=$?
printf 'drvPath patched : rc=%s %s\ndrvPath system  : rc=%s %s\n' \
  "$rc_p" "${drv_patched:-<none>}" "$rc_s" "${drv_system:-<none>}"
if [ "$rc_p" -eq 0 ] && [ "$rc_s" -eq 0 ] && [ "$drv_patched" = "$drv_system" ]; then
  pass "snapshot drvPath == system" "$drv_patched"
else
  fail "snapshot drvPath == system" "patched='${drv_patched}' system='${drv_system}'"
fi

# 6. the tree as it is — no snapshot, no cleanup, both binaries on the same
#    input. Identical results are the parity proof; a refusal is the
#    lazy-trees caveat and is reported verbatim.
# this tree is shared with a live agent session, so the check hashes the tree
# state around the two evals and only claims parity when nothing moved.
tree_hash() { git -C /etc/nixos status --porcelain=v1 -uall | sha256sum | cut -c1-12; }
printf '\n--- /etc/nixos as-is (dirty paths: %s, state %s) ---\n' \
  "$(git -C /etc/nixos status --porcelain -uall | wc -l)" "$(tree_hash)"
attempt=0
while [ "$attempt" -lt 3 ]; do
  attempt=$((attempt + 1))
  tree_before="$(tree_hash)"
  "$BIN" eval --raw "/etc/nixos#nixosConfigurations.trantor.config.system.build.toplevel.drvPath" \
    > /tmp/nixpatch-smoke-etc.out 2> /tmp/nixpatch-smoke-etc.err
  rc_etc_p=$?
  tree_mid="$(tree_hash)"
  "$SYS_NIX" eval --raw "/etc/nixos#nixosConfigurations.trantor.config.system.build.toplevel.drvPath" \
    > /tmp/nixpatch-smoke-etc-sys.out 2> /tmp/nixpatch-smoke-etc-sys.err
  rc_etc_s=$?
  tree_after="$(tree_hash)"
  [ "$tree_before" = "$tree_after" ] && break
  printf 'tree moved during attempt %s (%s -> %s), retrying\n' \
    "$attempt" "$tree_before" "$tree_after"
done
printf 'attempt=%s tree state: before=%s mid=%s after=%s\n' \
  "$attempt" "$tree_before" "$tree_mid" "$tree_after"
printf 'patched: rc=%s out=%s\n' "$rc_etc_p" "$(cat /tmp/nixpatch-smoke-etc.out)"
printf 'system : rc=%s out=%s\n' "$rc_etc_s" "$(cat /tmp/nixpatch-smoke-etc-sys.out)"
printf 'patched stderr (last 3):\n'
sed 's/^/  | /' /tmp/nixpatch-smoke-etc.err | tail -3
if [ "$rc_etc_p" -eq 0 ] && [ "$rc_etc_s" -eq 0 ]; then
  if [ "$(cat /tmp/nixpatch-smoke-etc.out)" = "$(cat /tmp/nixpatch-smoke-etc-sys.out)" ]; then
    pass "/etc/nixos as-is == system" "$(cat /tmp/nixpatch-smoke-etc.out)"
  elif [ "$tree_before" != "$tree_after" ]; then
    note "/etc/nixos as-is" "tree moved during the check — see the snapshot comparison"
  else
    fail "/etc/nixos as-is == system" "patched vs system drvPath differ on an unchanged tree"
  fi
elif [ "$rc_etc_p" -eq "$rc_etc_s" ]; then
  note "/etc/nixos as-is" "both binaries refused identically (expected without lazy-trees)"
else
  fail "/etc/nixos as-is" "patched rc=$rc_etc_p vs system rc=$rc_etc_s"
fi

# 7. flake metadata is a cheap extra; `nix search` is skipped (network + slow).
if "$BIN" flake metadata /etc/nixos --json > /tmp/nixpatch-smoke-meta.json 2> /dev/null \
  && jq -e '(.revision // .dirtyRevision // "") | length > 0' /tmp/nixpatch-smoke-meta.json > /dev/null 2>&1; then
  pass "flake metadata /etc/nixos" "rev=$(jq -r '.revision // .dirtyRevision' /tmp/nixpatch-smoke-meta.json | cut -c1-12)"
else
  note "flake metadata /etc/nixos" "no revision field in the metadata"
fi

# 8. untracked-but-referenced path, reproduced in an isolated copy so /etc/nixos
#    and the other session's work are never touched: commit a flake that points
#    at a package directory left untracked, then evaluate it with both binaries.
#    MEASURED (2026-11-02): both refuse with "is not tracked by Git" — the
#    system Nix reports `lazy-trees = true` in `nix config show`, yet lazy-trees
#    does not rescue untracked paths. So the precondition for ANY rollout is a
#    tree whose referenced paths are tracked or intent-to-add(`git add -N`), and
#    that is also the fix both binaries accept.
REPRO=/tmp/nixpatch-lazytrees
rm -rf "$REPRO"
mkdir -p "$REPRO/packages/questyle-ctl-probe"
git -C /etc/nixos archive HEAD | tar -x -C "$REPRO"
printf '{ runCommand }:\nrunCommand "lazy-trees-probe" { } "touch $out"\n' \
  > "$REPRO/packages/questyle-ctl-probe/default.nix"
sd '^}$' '  questyle-ctl-probe = pkgs.callPackage ../questyle-ctl-probe { };\n}' \
  "$REPRO/packages/flake/custom-packages.nix"
git -C "$REPRO" init -q
# the reference is committed, the referenced directory is not
git -C "$REPRO" add -A -- ':!packages/questyle-ctl-probe'
git -C "$REPRO" -c user.email=smoke@localhost -c user.name=smoke commit -qm "reference an untracked package"
printf '\n--- lazy-trees reproduction in %s (untracked: packages/questyle-ctl-probe) ---\n' "$REPRO"
"$BIN" eval --raw "$REPRO#questyle-ctl-probe.drvPath" > /tmp/nixpatch-smoke-repro-p.out 2> /tmp/nixpatch-smoke-repro-p.err
rc_repro_p=$?
"$SYS_NIX" eval --raw "$REPRO#questyle-ctl-probe.drvPath" > /tmp/nixpatch-smoke-repro-s.out 2> /tmp/nixpatch-smoke-repro-s.err
rc_repro_s=$?
printf 'patched: rc=%s\n' "$rc_repro_p"
sed 's/^/  | /' /tmp/nixpatch-smoke-repro-p.err | rg -N 'is not tracked by Git' | tail -1
printf 'system : rc=%s\n' "$rc_repro_s"
sed 's/^/  | /' /tmp/nixpatch-smoke-repro-s.err | rg -N 'is not tracked by Git' | tail -1
if [ "$rc_repro_p" -eq 1 ] && [ "$rc_repro_s" -eq 1 ] \
  && rg -q "is not tracked by Git" /tmp/nixpatch-smoke-repro-p.err /tmp/nixpatch-smoke-repro-s.err; then
  pass "untracked path: both refuse" "same error from both binaries"
else
  fail "untracked path: both refuse" "patched rc=$rc_repro_p system rc=$rc_repro_s"
fi

# ... and the documented cure: intent-to-add makes the path visible.
git -C "$REPRO" add -N packages/questyle-ctl-probe
drv_repro_p="$("$BIN" eval --raw "$REPRO#questyle-ctl-probe.drvPath" 2> /dev/null)"
rc_repro_p2=$?
drv_repro_s="$("$SYS_NIX" eval --raw "$REPRO#questyle-ctl-probe.drvPath" 2> /dev/null)"
rc_repro_s2=$?
printf 'after git add -N: patched rc=%s %s / system rc=%s %s\n' \
  "$rc_repro_p2" "$drv_repro_p" "$rc_repro_s2" "$drv_repro_s"
if [ "$rc_repro_p2" -eq 0 ] && [ "$rc_repro_s2" -eq 0 ] && [ "$drv_repro_p" = "$drv_repro_s" ]; then
  pass "git add -N unblocks both" "$drv_repro_p"
else
  fail "git add -N unblocks both" "patched='${drv_repro_p}' system='${drv_repro_s}'"
fi

# lazy-trees is a Determinate setting, not a property of this binary.
lt_sys="$(/run/current-system/sw/bin/nix config show 2> /dev/null | rg -N '^lazy-trees' || true)"
lt_pat="$("$BIN" config show 2> /dev/null | rg -N '^lazy-trees' || true)"
note "lazy-trees" "system: '${lt_sys:-<no such setting>}' | patched: '${lt_pat:-<no such setting>}'"
printf '\n=== %d mandatory failure(s) ===\n' "$fails"
exit $((fails > 0 ? 1 : 0))
