#!/usr/bin/env bash
# Report what a pending NixOS configuration is before building or switching it.
#
# Everything except the last section needs no build. Version, code name,
# revision and kernel come from one pure evaluation of the configuration; the
# package-level change set comes from the derivation closures — `nix-store -qR`
# over the pending toplevel's .drv and over the running system's .drv only reads
# already-instantiated .drv files. Only the exact version-to-version diff
# (`nix store diff-closures`, which walks realized outputs) needs an artifact, so
# it is printed solely when the result link already holds a build.
#
# The counts are by .drv *name*, i.e. "<pkg>-<version>.drv": a bump appears as
# one name gone and one added, and a package carrying several versions in one
# closure (nix, llvm, python3, qtbase) inflates them. Read the counts as an
# order of magnitude and the closure diff as the changelog.
#
# Usage: pending-version.sh [flake-ref] [host]
#   pending-version.sh                  # ./ and trantor
#   pending-version.sh /etc/nixos trantor
#
# Env:
#   PENDING_RESULT_LINK   build output link to inspect, default ./result

set -euo pipefail

flake_ref=${1:-.}
host=${2:-trantor}
result_link=${PENDING_RESULT_LINK:-result}

installable="${flake_ref}#nixosConfigurations.${host}.config"
# One evaluation for every field: a separate `nix eval` per attribute
# re-instantiates the whole configuration each time.
info=$(nix eval --json "$installable" --apply 'c: { version = c.system.nixos.version; codeName = c.system.nixos.codeName; revision = c.system.nixos.revision; kernel = c.boot.kernelPackages.kernel.version; toplevelOut = c.system.build.toplevel.outPath; toplevelDrv = c.system.build.toplevel.drvPath; }')

field() { jq -r --arg k "$1" '.[$k]' <<< "$info"; }

printf 'pending : %s (%s)\n' "$(field version)" "$(field codeName)"
printf 'revision: %s\n' "$(field revision)"
printf 'kernel  : %s\n' "$(field kernel)"
if command -v nixos-version > /dev/null 2>&1; then
  printf 'running : %s\n' "$(nixos-version)"
else
  printf 'running : (nixos-version not on PATH)\n'
fi

want=$(field toplevelOut)
have=$(readlink -f "$result_link" 2> /dev/null || true)
if [ "$have" = "$want" ]; then
  printf 'build   : %s matches the pending configuration\n' "$result_link"
else
  printf 'build   : %s is not the pending configuration (have %s, want %s)\n' \
    "$result_link" "$(basename "${have:-nothing}")" "$(basename "$want")"
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
nix-store -qR "$(field toplevelDrv)" \
  | sed 's|^/nix/store/[a-z0-9]*-||' | sort -u > "$tmp/pending"
current_system=$(readlink -f /run/current-system 2> /dev/null || true)
if [ -n "$current_system" ]; then
  nix-store -qR "$(nix-store -q --deriver "$current_system")" \
    | sed 's|^/nix/store/[a-z0-9]*-||' | sort -u > "$tmp/running"
  printf 'packages: %s added/upgraded, %s removed/downgraded (by drv name)\n' \
    "$(comm -13 "$tmp/running" "$tmp/pending" | wc -l)" \
    "$(comm -23 "$tmp/running" "$tmp/pending" | wc -l)"
else
  printf 'packages: %s in the pending closure (no /run/current-system to compare)\n' \
    "$(wc -l < "$tmp/pending")"
fi

if [ -n "$have" ] && [ "$have" != "$current_system" ]; then
  printf '\nclosure diff %s -> %s:\n' \
    "$(basename "${current_system:-no-running-system}")" "$(basename "$have")"
  nix store diff-closures "${current_system:-/run/current-system}" "$have"
fi
