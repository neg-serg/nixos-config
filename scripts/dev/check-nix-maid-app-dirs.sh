#!/usr/bin/env bash
# Verify every directory under modules/user/nix-maid/apps is either a real module
# or listed in the deny-list of that directory's default.nix.
#
# apps/default.nix auto-imports every sibling directory as a NixOS module and
# keeps an explicit deny-list for the data and plugin-bundle directories. A new
# plugin directory that is missing from that list fails the whole system
# evaluation, and only at evaluation time:
#
#   error: Path 'modules/user/nix-maid/apps/<name>/default.nix'
#          does not exist in Git repository "/etc/nixos"
#
# That reads like a flake/git problem rather than a missing list entry. This
# guard turns it into a fast local failure that names the line to add.
#
# Usage: check-nix-maid-app-dirs.sh [apps-dir]
#   apps-dir defaults to <repo-root>/modules/user/nix-maid/apps

set -euo pipefail

if [[ $# -gt 0 ]]; then
  APPS_DIR="$1"
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2> /dev/null || pwd)"
  APPS_DIR="$REPO_ROOT/modules/user/nix-maid/apps"
fi

if [[ ! -d "$APPS_DIR" ]]; then
  echo "nix-maid app directory not found: $APPS_DIR" >&2
  exit 1
fi

DEFAULT_NIX="$APPS_DIR/default.nix"
if [[ ! -f "$DEFAULT_NIX" ]]; then
  echo "missing $DEFAULT_NIX — the auto-import filter lives there" >&2
  exit 1
fi

echo "Checking nix-maid app directories against the deny-list..."

# Deny-list entries are spelled `n != "name"` inside the filter.
excluded="$(grep -oE 'n != "[^"]+"' "$DEFAULT_NIX" | sed -E 's/^n != "//; s/"$//' | sort -u || true)"
if [[ -z "$excluded" ]]; then
  echo "no deny-list entries found in $DEFAULT_NIX — is the filter still there?" >&2
  exit 1
fi

shopt -s nullglob dotglob

checked=0
missing=()
for path in "$APPS_DIR"/*/; do
  name="$(basename "$path")"
  checked=$((checked + 1))
  if [[ -f "$path/default.nix" ]]; then
    continue
  fi
  if ! grep -qxF "$name" <<< "$excluded"; then
    missing+=("$name")
  fi
done

if ((${#missing[@]} > 0)); then
  {
    echo
    echo "FAIL: ${#missing[@]} directory(ies) are neither a module nor denied:"
    for name in "${missing[@]}"; do
      echo "  $name (no default.nix)"
    done
    echo
    echo "Add each one to the deny-list in $DEFAULT_NIX:"
    for name in "${missing[@]}"; do
      echo "      && n != \"$name\""
    done
    echo
    echo "Otherwise the next system build fails at evaluation with:"
    echo "  error: Path '.../apps/<name>/default.nix' does not exist in Git repository"
  } >&2
  exit 1
fi

# A filter entry with no matching file or directory is harmless (the filter
# simply never sees it) but it is dead configuration — report it without
# failing. The `-e` test is deliberate: the filter's own `n != "default.nix"`
# guard is an entry too, and that name of course exists as a file.
stale=()
while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  if [[ ! -e "$APPS_DIR/$name" ]]; then
    stale+=("$name")
  fi
done <<< "$excluded"

if ((${#stale[@]} > 0)); then
  echo "warning: ${#stale[@]} filter entry(ies) match no file or directory (dead but harmless):"
  for name in "${stale[@]}"; do
    echo "  $name"
  done
fi

echo "OK: $checked director(ies) checked, $(wc -l <<< "$excluded" | tr -d ' ') filter entries"
