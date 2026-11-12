#!/usr/bin/env bash
# Bump an in-tree Rust project's version in one place. Every derivation under
# packages/ reads `version` from the project manifest
# (`(lib.importTOML ./Cargo.toml).package.version`), and the binary reports
# CARGO_PKG_VERSION from the same file, so a bump is the manifest plus the
# lockfiles that record the crate's own version — nothing in Nix changes.
#
# Usage: bump-version.sh <package> [<version>]
#   <package>  directory name under packages/ (or a path to the project)
#   <version>  target version; omitted = increment the patch component
#
# Lockfiles updated when they carry the crate: the one next to the manifest and
# packages/Cargo.lock (the workspace lock, for its members). cargo then checks
# the result with `--locked --no-deps --offline` before the script exits.
set -euo pipefail

# shellcheck source=lib.sh disable=SC1091
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

die() {
  printf 'bump-version: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat >&2 << 'EOF'
Usage: bump-version.sh <package> [<version>]
  <package>  directory name under packages/ (or a path to the project)
  <version>  target version; omitted = increment the patch component
EOF
}

[ "$#" -ge 1 ] || {
  usage
  exit 2
}

root=$(repo_root)
arg=$1
if [ -d "$arg" ]; then
  dir=$(cd "$arg" && pwd)
elif [ -d "$root/packages/$arg" ]; then
  dir="$root/packages/$arg"
else
  die "no such project: $arg (expected a path or packages/<name>)"
fi

manifest="$dir/Cargo.toml"
[ -f "$manifest" ] || die "$dir has no Cargo.toml"

# Read a key from the `[package]` table only: dependency tables and the
# workspace's own sections carry unrelated `version` keys.
section_value() {
  awk -v key="$2" '
    /^\[/ { section = $0; gsub(/[][]/, "", section) }
    section == "package" && !done && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      value = $0
      sub(/^[^"]*"/, "", value)
      sub(/".*$/, "", value)
      print value
      done = 1
    }
  ' "$1"
}

crate=$(section_value "$manifest" name)
[ -n "$crate" ] || die "no [package] name in $manifest"
current=$(section_value "$manifest" version)
[ -n "$current" ] || die "no [package] version in $manifest"

if [ "$#" -ge 2 ] && [ -n "${2// /}" ]; then
  target=$2
else
  if ! [[ $current =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    die "cannot auto-increment '$current' (not X.Y.Z); pass the target version"
  fi
  target="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.$((BASH_REMATCH[3] + 1))"
fi

if [ "$target" = "$current" ]; then
  printf '%s is already at %s\n' "$crate" "$current"
  exit 0
fi

# Rewrite only the [package] version line; the file keeps its mode and every
# other byte, so the diff stays one line.
tmp=$(mktemp "$dir/.Cargo.toml.XXXXXX")
if ! awk -v ver="$target" '
  /^\[/ { section = $0; gsub(/[][]/, "", section) }
  section == "package" && !done && /^[[:space:]]*version[[:space:]]*=/ {
    print "version = \"" ver "\""
    done = 1
    next
  }
  { print }
  END { exit(done ? 0 : 3) }
' "$manifest" > "$tmp"; then
  rm -f "$tmp"
  die "could not rewrite the [package] version in $manifest"
fi
chmod --reference="$manifest" "$tmp"
mv "$tmp" "$manifest"
printf 'manifest  %s: %s -> %s\n' "${manifest#"$root"/}" "$current" "$target"

# A Cargo.lock entry is `[[package]]`, then `name = "<crate>"`, then its
# version; only the block for this crate is touched.
bump_lock() {
  local lock=$1
  [ -f "$lock" ] || return 0
  grep -qx "name = \"$crate\"" "$lock" || return 0
  tmp=$(mktemp "$(dirname "$lock")/.lock.XXXXXX")
  awk -v crate="$crate" -v ver="$target" '
    /^\[\[package\]\]/ { cur = "" }
    /^name = "/ { cur = $0; sub(/^name = "/, "", cur); sub(/"$/, "", cur) }
    cur == crate && /^version = "/ {
      print "version = \"" ver "\""
      next
    }
    { print }
  ' "$lock" > "$tmp"
  chmod --reference="$lock" "$tmp"
  mv "$tmp" "$lock"
  printf 'lockfile  %s\n' "${lock#"$root"/}"
}

bump_lock "$dir/Cargo.lock"
bump_lock "$root/packages/Cargo.lock"

# The lockfiles are authoritative for the Nix build (cargoLock.lockFile), so a
# stale one fails there much later; catch it here instead.
if command -v cargo > /dev/null 2>&1; then
  if ! (cd "$dir" && cargo metadata --locked --no-deps --offline --format-version 1 > /dev/null); then
    die "cargo rejects the lockfiles after the bump: run 'cargo update -p $crate --offline' in $dir"
  fi
fi

printf '%s %s: the derivations read this from %s\n' "$crate" "$target" "${manifest#"$root"/}"
