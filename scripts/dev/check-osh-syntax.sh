#!/usr/bin/env bash
# Parse-check every tracked shell script with osh -n (the bash-compatible
# parser from Oils, https://oils.pub). Keeps the shell corpus runnable as a
# drop-in under osh: a syntax-level bashism that osh rejects fails the lint
# suite. Runtime-only incompatibilities are NOT caught by -n (e.g. bare
# associative-array keys, OILS-ERR-101) — keep those out by convention; see
# the quoted-key fix in files/art/fun-art/bonsai.sh.
#
# Usage: bash scripts/dev/check-osh-syntax.sh [REPO_ROOT]

set -euo pipefail

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2> /dev/null || pwd)}"
cd "$REPO_ROOT"

if ! command -v osh > /dev/null 2>&1; then
  echo "WARNING: osh not found; skipping OSH syntax check" >&2
  exit 0
fi

fail=0
count=0
while IFS= read -r -d '' file; do
  # Only files that declare a POSIX/Bash shebang — the same filter as the
  # lint step in Justfile, but covering extensionless scripts too.
  if head -n 1 "$file" | grep -qE '^#!\s*/(usr/)?bin/(env\s+)?(ba)?sh\b'; then
    ((count++)) || true
    if ! output=$(osh -n "$file" 2>&1); then
      echo "ERROR: $file"
      echo "$output" | head -5
      echo ""
      fail=1
    fi
  fi
done < <(git ls-files -z)

echo "Checked $count shell script(s) with osh -n"
if [[ $fail -ne 0 ]]; then
  echo "FAILED: osh parse errors found (see above)"
  exit 1
fi
echo "All shell scripts parse under osh!"
