#!/usr/bin/env bash
# shellcheck disable=SC2154  # pmap_ok/pmap_failed are set by pmap in lib.sh
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

# Worker for pmap: `pleamar --check` on one scene, diagnostics printed only on
# failure. pmap buffers each call and replays the blocks in scene order, so the
# failure report still reads like the serial loop this replaced.
plm_one() {
  local f=$1 output
  if ! output=$(pleamar --check "$f" 2>&1); then
    printf 'ERROR: %s\n%s\n\n' "$f" "$output"
    return 1
  fi
}

# The compiler is a per-file process with no shared state; check the scenes
# concurrently (bounded by pmap) instead of one at a time.
if ! pmap -0 -- plm_one < <(printf '%s\0' "${SCENES[@]}"); then
  echo "FAILED: $pmap_failed of ${#SCENES[@]} scene(s) failed pleamar --check"
  exit 1
fi

echo "OK: all ${#SCENES[@]} scene(s) compile"
