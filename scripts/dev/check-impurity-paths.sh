#!/usr/bin/env bash
# Verify that all paths referenced in impurity.link calls exist in the repository.
# This helps catch broken symlinks before they cause runtime issues.

set -euo pipefail

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2> /dev/null || pwd)}"
cd "$REPO_ROOT"

errors=0

# Extract impurity.link paths from Nix files and verify they exist
# Pattern: impurity.link <path> where path is a Nix path expression
# We look for common patterns like:
#   impurity.link ./path
#   impurity.link ../path
#   impurity.link (varName + /subpath)

echo "Checking impurity.link paths in $REPO_ROOT..."

# Direct paths like ./../../files/nvim or ../../../files/gui/swayimg
grep -roP '(impurity\.link|linkImpure)\s+\.+/[^;]+' modules/ 2> /dev/null | while read -r line; do
  file=$(echo "$line" | cut -d: -f1)
  match=$(echo "$line" | cut -d: -f2-)

  # Extract the path after the function call
  rel_path=$(echo "$match" | sed -E 's/.*(impurity\.link|linkImpure)\s+//' | sed 's/;$//')

  # Directory of the source file
  dir=$(dirname "$file")

  # Resolve/Check relative to the source file location
  if [[ ! -e "$dir/$rel_path" ]]; then
    echo "ERROR: Path does not exist: $dir/$rel_path (referenced in $file)"
    ((errors++)) || true
  fi
done

# Paths defined as variables - check the source directories exist
dirs_to_check=(
  "files/nvim"
  "files/gui/hypr"
  "files/gui/hypr/bindings"
  "files/gui/hypr/animations"
  "files/gui/hypr/hyprlock"
  "files/gui/swayimg"
  "files/rmpc"
  "files/gui/ncpamixer.conf"
  "files/walker"
  "files/walker/themes"
  "files/kitty"
  "files/tmux"

  "files/quickshell"
  "files/fastfetch"
  "files/gui/vicinae-extensions"
  "files/shell/zsh/neg.omp.json"
)

for dir in "${dirs_to_check[@]}"; do
  if [[ ! -e "$dir" ]]; then
    echo "ERROR: Expected impurity.link source missing: $dir"
    ((errors++)) || true
  else
    echo "OK: $dir"
  fi
done

if [[ $errors -gt 0 ]]; then
  echo ""
  echo "FAILED: $errors path(s) missing"
  exit 1
fi

echo ""
echo "All impurity.link paths verified successfully!"
