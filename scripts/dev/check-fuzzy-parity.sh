#!/usr/bin/env bash
set -euo pipefail

# Parity gate for the JS port of the lusty-fuzzy matcher (files/quickshell/Helpers/Fuzzy.js).
#
# Two checks:
#   1. scripts/dev/check-fuzzy-parity.mjs replays the golden vectors
#      (files/quickshell/Helpers/tests/fuzzy-vectors.json) against the port —
#      result count, order, score (1e-9) and match spans must match the crate.
#   2. When the deployed `lusty` supports `--fuzzy-vectors`, the fixture is
#      re-derived from the crate and compared byte for byte, so a crate change
#      cannot leave a stale fixture behind.
#
# The deployed binary is never executed to *probe* for the flag: an older lusty
# (flake input predating the crate) would treat it as a path, drop into its TUI
# and wait for a terminal — the flag literal is grepped out of the binary instead.
#
# Usage: check-fuzzy-parity.sh [fixture.json]

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$script_dir/../.." && pwd)"
fixture="${1:-$REPO_ROOT/files/quickshell/Helpers/tests/fuzzy-vectors.json}"

if ! command -v node > /dev/null 2>&1; then
  echo "check-fuzzy-parity: node not found, skipping" >&2
  exit 0
fi

node "$script_dir/check-fuzzy-parity.mjs" "$fixture"

lusty_bin="${LUSTY_BIN:-$(command -v lusty || true)}"
if [[ -z "$lusty_bin" ]]; then
  echo "check-fuzzy-parity: lusty not on PATH, fixture freshness not re-checked" >&2
  exit 0
fi

if ! strings "$lusty_bin" 2> /dev/null | grep -q -- "--fuzzy-vectors"; then
  echo "check-fuzzy-parity: this lusty build has no --fuzzy-vectors (flake input older than the crate), skipping freshness check" >&2
  exit 0
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Rebuild a corpus from the fixture (it carries labels and queries) so the check
# does not depend on the lusty checkout being present.
python3 - "$fixture" "$work/corpus.txt" <<'PY'
import json, sys
fixture, out = sys.argv[1], sys.argv[2]
data = json.load(open(fixture))
with open(out, "w") as fh:
    fh.write("# regenerated from the fixture by check-fuzzy-parity.sh\n")
    for label in data["labels"]:
        fh.write("label: %s\n" % label)
    for case in data["cases"]:
        fh.write("query: %s\n" % case["query"])
PY

if ! timeout -k 2 60 "$lusty_bin" --fuzzy-vectors --corpus "$work/corpus.txt" --anchor none \
  < /dev/null > "$work/vectors.json" 2> "$work/err"; then
  cat "$work/err" >&2
  exit 1
fi

if ! diff -u "$fixture" "$work/vectors.json" > "$work/diff"; then
  echo "check-fuzzy-parity: the committed fixture no longer matches the deployed lusty:" >&2
  head -40 "$work/diff" >&2
  echo "regenerate with scripts/dev/gen-fuzzy-vectors.sh" >&2
  exit 1
fi

echo "check-fuzzy-parity: fixture matches the deployed lusty build"
