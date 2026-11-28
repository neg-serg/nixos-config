#!/usr/bin/env bash
# Refresh the vendored Google prose style in files/vale/styles/Google from an
# upstream tag of vale-cli/Google.
#
# The style is vendored, not synced: home-manager links StylesPath into the nix
# store, so `vale sync` cannot write there. Tarballs are not an option either —
# codeload.github.com is blocked on this host — hence the contents API plus raw
# files. Every download lands in a temporary directory first, so a network
# failure never leaves a half-updated style behind.
#
# Usage: vale-update.sh [tag]        (default: the latest upstream release)
#
# The version stamped in files/vale/.vale.ini is rewritten in place; a rebuild
# is needed before the editor sees the new rules.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root)"
STYLE_DIR="$REPO_ROOT/files/vale/styles/Google"
API=https://api.github.com/repos/vale-cli/Google
RAW=https://raw.githubusercontent.com/vale-cli/Google

for tool in curl jq; do
  if ! command -v "$tool" > /dev/null 2>&1; then
    printf 'vale-update: %s is required\n' "$tool" >&2
    exit 1
  fi
done

tag=${1:-}
if [ -z "$tag" ]; then
  tag=$(curl -fsSL "$API/releases/latest" | jq -r '.tag_name // empty') || tag=""
  if [ -z "$tag" ]; then
    printf 'vale-update: cannot read the latest upstream release\n' >&2
    exit 1
  fi
fi

# The rule set is everything in Google/ (rules, meta.json, vocab.txt); LICENSE
# sits at the repository root, not inside Google/.
listing=$(curl -fsSL "$API/contents/Google?ref=$tag") || {
  printf 'vale-update: no upstream tag or release named %s\n' "$tag" >&2
  exit 1
}
names=$(printf '%s\n' "$listing" | jq -r '.[].name')
if [ -z "$names" ]; then
  printf 'vale-update: upstream file list for %s is empty\n' "$tag" >&2
  exit 1
fi

tmp=$(mktemp -d "${TMPDIR:-/tmp}/vale-update.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT

# shellcheck disable=SC2086  # one plain file name per line, splitting is wanted
for name in $names; do
  curl -fsSL "$RAW/$tag/Google/$name" -o "$tmp/$name"
done
curl -fsSL "$RAW/$tag/LICENSE" -o "$tmp/LICENSE"

mkdir -p "$STYLE_DIR"
# shellcheck disable=SC2086
for name in $names; do
  install -m 0644 -- "$tmp/$name" "$STYLE_DIR/$name"
done
install -m 0644 -- "$tmp/LICENSE" "$STYLE_DIR/LICENSE"

sed -i "s#vale-cli/Google v[0-9][^)]*#vale-cli/Google $tag#" \
  "$REPO_ROOT/files/vale/.vale.ini"

printf 'vale-update: %s written to %s\n' "$tag" "${STYLE_DIR#"$REPO_ROOT"/}"
git -C "$REPO_ROOT" diff --stat -- files/vale || true
printf 'Rebuild to activate: the deployed StylesPath is a store copy.\n'
