#!/usr/bin/env bash
# check-nix-wrapper.sh <wrapper> — guard for packages/local-bin/bin/nix, the
# ~/.local/bin shim that keeps `nix …` usable when $HOME is read-only (the DSH
# workspace-write sandbox).
#
# Contract pinned here:
#   • a writable default cache root is left alone (the shim is a pure passthrough);
#   • an unusable default cache root moves XDG_CACHE_HOME to the scratch root;
#   • an unusable scratch root leaves the environment alone and says so;
#   • the real binary always receives the arguments unchanged;
#   • a missing real binary exits 127 instead of silently doing nothing.
#
# Hermetic: the "real nix" is a fixture that prints what it received, the cache
# roots live in a per-case temporary tree, and nothing touches the store.
set -euo pipefail

wrapper="${1:?usage: check-nix-wrapper.sh <wrapper>}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

real="$work/real-nix"
# The fixture needs an absolute shebang: a Nix build sandbox has no /usr/bin/env.
{
  printf '#!%s\n' "$BASH"
  cat << 'EOF'
printf 'cache=%s\n' "${XDG_CACHE_HOME:-}"
printf 'args=%s\n' "$*"
EOF
} > "$real"
chmod +x "$real"

# shim <cache-root> <scratch-root> [args…] → stdout/stderr/status of the wrapper
shim() {
  local cache=$1 scratch=$2
  shift 2
  XDG_CACHE_HOME="$cache" \
    NIX_SANDBOX_CACHE="$scratch" \
    NIX_SANDBOX_REAL="$real" \
    bash "$wrapper" "$@"
}

# 1. Writable default cache: the wrapper must not relocate, and must forward
#    every argument (including one with a space) verbatim.
mkdir -p "$work/writable/nix"
out=$(shim "$work/writable" "$work/scratch-a" flake update "a b")
[ "$out" = "cache=$work/writable
args=flake update a b" ] || fail "writable cache was not passed through: $out"

# 2. Unusable default cache (a regular file where the fetcher-locks dir would
#    go, so no permission dance is needed): XDG_CACHE_HOME moves to the scratch
#    root, arguments still unchanged.
mkdir -p "$work/blocked"
: > "$work/blocked/nix"
out=$(shim "$work/blocked" "$work/scratch-b" flake update)
[ "$out" = "cache=$work/scratch-b
args=flake update" ] || fail "read-only cache was not relocated: $out"

# 3. Unusable scratch root too (regular file again): the wrapper must warn and
#    pass the original environment through, not invent a cache.
: > "$work/scratch-c"
err=$(shim "$work/blocked" "$work/scratch-c" eval --raw --expr 1 2>&1 > /dev/null)
out=$(shim "$work/blocked" "$work/scratch-c" eval --raw --expr 1 2> /dev/null)
case "$err" in
  *"read-only and no usable scratch cache"*) ;;
  *) fail "missing warning for an unusable scratch root: $err" ;;
esac
[ "$out" = "cache=$work/blocked
args=eval --raw --expr 1" ] || fail "environment was mutated without a scratch root: $out"

# 4. A missing real binary is a hard failure with a shell-standard 127.
set +e
NIX_SANDBOX_REAL="$work/absent" XDG_CACHE_HOME="$work/writable" \
  bash "$wrapper" --version > /dev/null 2>&1
status=$?
set -e
[ "$status" -eq 127 ] || fail "missing real binary exited $status, expected 127"

printf 'check: nix wrapper OK (4 cases)\n'
