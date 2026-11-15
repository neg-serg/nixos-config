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

# One awk pass over all the files instead of one awk per file: the per-file
# process was the gate's whole cost (400 files spent ~0.8 s on it). FNR resets
# the lookback state at every file, so the allow-absolute-home exception on the
# line or the two lines above still works exactly as before.
fail=0
if ! find modules hosts lib -type f -name '*.nix' -print0 2> /dev/null \
  | xargs -0 -r awk '
    FNR == 1 {
      if (hits != "") {
        printf "%s:\n%s", file, hits > "/dev/stderr"
        found = 1
      }
      file = FILENAME
      hits = ""
      prev = ""
      prev2 = ""
    }
    { raw = $0; code = $0; sub(/#.*/, "", code)
      if (code ~ /(^|[^A-Za-z0-9._\/-])\/home\/[A-Za-z0-9._-]+/ &&
          raw !~ /allow-absolute-home/ &&
          prev !~ /allow-absolute-home/ &&
          prev2 !~ /allow-absolute-home/) {
        hits = hits FNR ":" raw "\n"
      }
      prev2 = prev
      prev = raw
    }
    END {
      if (hits != "") {
        printf "%s:\n%s", file, hits > "/dev/stderr"
        found = 1
      }
      exit found ? 1 : 0
    }
  '; then
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "Absolute home path guard: FAILED (use config.lib.neg.homeDir or pass homeDir)" >&2
  exit 1
fi
echo "Absolute home path guard: OK"
