#!/usr/bin/env bash
set -euo pipefail

# Regenerate files/quickshell/Helpers/tests/fuzzy-vectors.json from the crate.
#
# The fixture is the contract between the Rust matcher (lusty: crates/lusty-fuzzy)
# and its JS port (files/quickshell/Helpers/Fuzzy.js). Regenerate it whenever the
# crate's scoring, span extraction or ranking policy changes, and commit it in the
# same change — scripts/dev/check-fuzzy-parity.sh replays it against the port.
#
# Usage: gen-fuzzy-vectors.sh [corpus.txt] [lusty-binary]
#   corpus defaults to <lusty checkout>/crates/lusty-fuzzy/tests/corpus/menu.txt
#   (LUSTY_SRC overrides the checkout path); the binary defaults to LUSTY_BIN or
#   `lusty` on PATH.

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/../.." && pwd)"
lusty_src="${LUSTY_SRC:-$HOME/src/lusty}"
corpus="${1:-$lusty_src/crates/lusty-fuzzy/tests/corpus/menu.txt}"
lusty_bin="${2:-${LUSTY_BIN:-$(command -v lusty || true)}}"
fixture="$repo_root/files/quickshell/Helpers/tests/fuzzy-vectors.json"

if [[ ! -r "$corpus" ]]; then
  echo "gen-fuzzy-vectors: corpus not found: $corpus" >&2
  echo "  pass a corpus path or set LUSTY_SRC to the lusty checkout" >&2
  exit 2
fi
if [[ -z "$lusty_bin" ]]; then
  echo "gen-fuzzy-vectors: no lusty binary (pass one or set LUSTY_BIN)" >&2
  exit 2
fi

# Menus: no first-letter anchor (people type a word from the middle of a label).
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
"$lusty_bin" --fuzzy-vectors --corpus "$corpus" --anchor none > "$tmp"
mv "$tmp" "$fixture"
echo "gen-fuzzy-vectors: wrote $fixture ($(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(len(d["labels"]), "labels,", len(d["cases"]), "queries")' "$fixture"))"
