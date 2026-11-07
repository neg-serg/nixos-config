#!/usr/bin/env bash
# Bump the flake inputs that point at neg's own repositories, keep only the
# bumps that still evaluate, and commit the lock (never push).
#
# Why a separate recipe: `nix flake update` moves every pin at once, nixpkgs
# included, and one bad pin hides the rest. Own inputs are the ones neg can
# move to a branch head without a decision; heavy inputs are opt-in because
# their rebuild (aurora: Rust/Vulkan, iosevka-neg: font) is long and the pin is
# part of the package's release choice.
#
# Guards: git work tree, branch main, clean tree (untracked files ignored — the
# same rule rollout-watch uses), nix and jq on PATH. Each input keeps its bump
# only when the toplevel still evaluates; a failing bump is restored from the
# pre-bump copy and the loop continues with the rest. The result is one
# `[flake] Bump own project inputs` commit; rollout-watch deploys it on its next
# tick like any other commit on main.
#
# The repo is resolved from this script's location (scripts/dev/../..), so the
# timer unit needs no WorkingDirectory. --allow-skip is what the weekly unit
# passes: a dirty tree or another branch is then a quiet skip, not a failure.
#
# Usage: flake-bump-own.sh [--all] [--no-commit] [--allow-skip]
#   --all         also bump aurora-src and iosevka-neg
#   --no-commit   leave the updated flake.lock in the working tree for review
#   --allow-skip  exit 0 instead of 1 when the tree is dirty or not on main
#   -h, --help    print this help

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh disable=SC1091
. "$script_dir/lib.sh"

usage() {
  # Print the header's usage block: from `# Usage:` to the end of the comment block.
  awk '/^# Usage:/ { p = 1 } p && !/^#/ { exit } p { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
}

die() {
  printf 'flake-bump-own: %s\n' "$*" >&2
  exit 1
}

# A precondition the weekly timer should not treat as a failure. Manual runs
# keep the non-zero exit; the timer passes --allow-skip and stays quiet.
skip() {
  if [ "$allow_skip" -eq 1 ]; then
    printf 'flake-bump-own: skipped: %s\n' "$*" >&2
    exit 0
  fi
  die "$*"
}

include_heavy=0
commit=1
allow_skip=0
while [ $# -gt 0 ]; do
  case "$1" in
    --all) include_heavy=1 ;;
    --no-commit) commit=0 ;;
    --allow-skip) allow_skip=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unknown argument '$1' (see --help)" ;;
  esac
  shift
done

repo=$(repo_root "$(cd -- "$script_dir/../.." && pwd)")
[ -d "$repo/.git" ] || die "$repo is not a git work tree"

branch=$(git -C "$repo" symbolic-ref --quiet --short HEAD || true)
[ "$branch" = main ] || skip "HEAD is on ${branch:-a detached head}, not main"

status=$(git -C "$repo" status --porcelain --untracked-files=no)
[ -z "$status" ] || skip "working tree is dirty; commit or stash the changes first"

command -v nix > /dev/null 2>&1 || die "nix is not on PATH"
command -v jq > /dev/null 2>&1 || die "jq is not on PATH"

gate="$script_dir/nixos-eval-gate.sh"
[ -x "$gate" ] || die "eval gate is missing: $gate"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/flake-bump-own.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
backup="$tmp/flake.lock"

lock_rev() {
  jq -r --arg name "$1" '.nodes[$name].locked.rev // empty' "$repo/flake.lock"
}

# Inputs that are neg's own repositories and cheap enough to rebuild weekly.
inputs=(raise wl lusty neg-pkgs hyprscratch rsmetrx nix-cache-pin)
if [ "$include_heavy" -eq 1 ]; then
  inputs+=(aurora-src iosevka-neg)
fi

moved=()
failed=()
for input in "${inputs[@]}"; do
  before=$(lock_rev "$input")
  if [ -z "$before" ]; then
    printf 'flake-bump-own: input %s is not in flake.lock, skipped\n' "$input" >&2
    continue
  fi
  printf 'flake-bump-own: %s at %s\n' "$input" "${before:0:8}"

  cp -p "$repo/flake.lock" "$backup"
  if ! (cd "$repo" && nix flake update "$input" > /dev/null); then
    cp -p "$backup" "$repo/flake.lock"
    failed+=("$input: lock update failed")
    continue
  fi

  after=$(lock_rev "$input")
  if [ "$after" = "$before" ]; then
    printf '  already at %s\n' "${before:0:8}"
    continue
  fi

  printf '  %s -> %s, checking eval\n' "${before:0:8}" "${after:0:8}"
  if "$gate" --drv > /dev/null 2> "$tmp/eval.log"; then
    moved+=("$input: ${before:0:8} -> ${after:0:8}")
  else
    cp -p "$backup" "$repo/flake.lock"
    failed+=("$input: toplevel eval failed")
    tail -3 "$tmp/eval.log" | sed 's/^/  /' >&2
  fi
done

if [ "${#failed[@]}" -gt 0 ]; then
  printf 'flake-bump-own: skipped:\n' >&2
  printf '  %s\n' "${failed[@]}" >&2
fi

if [ "${#moved[@]}" -eq 0 ]; then
  echo 'flake-bump-own: no own input moved'
  if [ "${#failed[@]}" -eq 0 ]; then exit 0; else exit 1; fi
fi

printf 'flake-bump-own: moved:\n'
printf '  %s\n' "${moved[@]}"

if [ "$commit" -eq 0 ]; then
  git -C "$repo" diff --stat -- flake.lock
  echo 'flake-bump-own: flake.lock left uncommitted (--no-commit)'
  if [ "${#failed[@]}" -eq 0 ]; then exit 0; else exit 1; fi
fi

changed=$(git -C "$repo" status --porcelain --untracked-files=no)
[ "$changed" = " M flake.lock" ] || die "unexpected working-tree changes:$changed"

{
  echo '[flake] Bump own project inputs'
  echo
  echo 'Generated by scripts/dev/flake-bump-own.sh; each input was kept only if'
  echo 'the toplevel still evaluated. Not pushed: review and push by hand.'
  echo
  printf -- '- %s\n' "${moved[@]}"
  if [ "${#failed[@]}" -gt 0 ]; then
    echo
    echo 'Skipped:'
    printf -- '- %s\n' "${failed[@]}"
  fi
} > "$tmp/message"

git -C "$repo" add flake.lock
git -C "$repo" commit --quiet -F "$tmp/message"
printf 'flake-bump-own: committed %s\n' "$(git -C "$repo" rev-parse --short HEAD)"

if [ "${#failed[@]}" -eq 0 ]; then exit 0; else exit 1; fi
