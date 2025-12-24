#!/usr/bin/env bash

# Find packages in environment.systemPackages (or similar lists) that lack a comment.
# Enforces the convention: pkgs.foo # description

set -euo pipefail

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2> /dev/null || pwd)}"
cd "$REPO_ROOT"

EXIT_CODE=0

echo "Checking for unannotated package references in modules/..."

# Pattern for packages: pkgs. or inputs. followed by word chars
PKG_PATTERN='(pkgs|inputs)\.[a-zA-Z0-9_-]+'

# Exclude list (regex) for non-package references or constructors
EXCLUDE_PATTERN='(with pkgs|inherit|pkgs\.lib|pkgs\.stdenv|pkgs\.system|pkgs\.config|pkgs\.callPackage|pkgs\.write|pkgs\.fetch|pkgs\.python|pkgs\.build|pkgs\.runCommand|pkgs\.symlinkJoin|pkgs\.override|pkgs\.neg\s*=|pkgs\.recurseIntoAttrs)'

# We look for lines in modules/ that have a package reference but no '#' comment.
# We focus on lines where pkgs. starts after some whitespace (common for list items).
results=$(grep -rnE "${PKG_PATTERN}" modules/ \
    | grep -v '#' \
    | grep -vE "${EXCLUDE_PATTERN}" \
    | grep -E '^modules/.*:[0-9]+:\s*(pkgs|inputs)\.' || true)

if [ -n "$results" ]; then
    echo "Error: Found unannotated package references:"
    echo "--------------------------------------------------------------------------------"
    echo "$results"
    echo "--------------------------------------------------------------------------------"
    echo ""
    echo "Please add a short inline comment to each package, e.g.:"
    echo "  pkgs.hello # a friendly greeting tool"
    EXIT_CODE=1
else
    echo "All package references appear to have annotations. Good job!"
fi

exit "$EXIT_CODE"
