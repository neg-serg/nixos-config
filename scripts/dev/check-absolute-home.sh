#!/usr/bin/env bash
# Guard: no absolute /home/<user> paths in module, host or lib code.
#
# A $HOME-relative path written as a literal made the tree host-specific: a
# renamed user or a second host silently points at /home/neg. Modules use
# config.lib.neg.homeDir (derived from users.main); lib helpers take homeDir as
# an argument. flake.nix (a machine-local path input) and packages/ (no config
# in a package function) are out of scope on purpose.
#
# An exception can be marked with `# allow-absolute-home: <reason>` on the line
# or the line right before it.
#
# Usage: check-absolute-home.sh [repo-root]
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "$@")"
cd "$REPO_ROOT"

fail=0
while IFS= read -r -d '' file; do
  hits=$(
    awk '
      { raw = $0; code = $0; sub(/#.*/, "", code)
        if (code ~ /(^|[^A-Za-z0-9._\/-])\/home\/[A-Za-z0-9._-]+/ &&
            raw !~ /allow-absolute-home/ &&
            prev !~ /allow-absolute-home/) {
          printf "%d:%s\n", FNR, raw
        }
        prev = raw
      }
    ' "$file"
  )
  if [ -n "$hits" ]; then
    printf '%s:\n%s\n' "$file" "$hits" >&2
    fail=1
  fi
done < <(find modules hosts lib -type f -name '*.nix' -print0 2> /dev/null)

if [ "$fail" -ne 0 ]; then
  echo "Absolute home path guard: FAILED (use config.lib.neg.homeDir or pass homeDir)" >&2
  exit 1
fi
echo "Absolute home path guard: OK"
