#!/usr/bin/env bash
# Compile-check every pleamar scene in the repository with `pleamar --check`.
#
# The compiler is the only thing that can decide whether a .plm file is valid:
# pleamar has no keyword outside its grammar, and a scene that looks right can
# still reference an option that does not exist. This gate is the repo-wide
# counterpart of the per-edit `pleamar --check <file>` rule in
# files/pleamar/AGENTS.md.
#
# The pleamar binary may not be on PATH yet (it is being built separately), so a
# missing binary is a skip with a notice, matching the rustfmt/selene gates in
# the Justfile: no false failures on machines without the tool. It starts
# checking the moment the binary appears in PATH.
#
# Exit status: 1 when at least one scene fails to compile, 0 otherwise.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "${1:-}")"

command -v pleamar > /dev/null 2>&1 || {
  echo "pleamar not found — skipping .plm scene check (build/install pkgs.pleamar to enable it)"
  exit 0
}

cd "$REPO_ROOT"

# -z so paths with spaces survive. --cached covers tracked (and intent-to-add)
# scenes, --others the not-yet-added ones (untracked but not ignored): a new
# scene is checked during development, before it is ever `git add`ed.
FILES=()
while IFS= read -r -d '' f; do
  FILES+=("$f")
done < <(git ls-files --cached --others --exclude-standard -z -- '*.plm')

# `pleamar --check` opens scenes only: it refuses `library` files (they are
# checked through the scenes that import them) and `part` files (includes that
# are read by whoever includes them). Both are skipped here, so the gate says
# the same thing the compiler does instead of failing on a valid library.
SCENES=()
skipped=0
for f in "${FILES[@]}"; do
  if grep -qE '^[[:space:]]*(library|part)[[:space:]]' "$f"; then
    skipped=$((skipped + 1))
    continue
  fi
  SCENES+=("$f")
done

echo "pleamar --check: ${#SCENES[@]} scene(s), ${skipped} library/part file(s) skipped"

REPORT="$(mktemp)"
trap 'rm -f "$REPORT"' EXIT
failures=0
for f in "${SCENES[@]}"; do
  if ! output="$(pleamar --check "$f" 2>&1)"; then
    {
      echo "ERROR: $f"
      printf '%s\n\n' "$output"
    } >> "$REPORT"
    failures=$((failures + 1))
  fi
done

if [ "$failures" -gt 0 ]; then
  cat "$REPORT"
  echo "FAILED: $failures of ${#SCENES[@]} scene(s) failed pleamar --check"
  exit 1
fi

echo "OK: all ${#SCENES[@]} scene(s) compile"
