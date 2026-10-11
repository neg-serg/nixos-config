#!/usr/bin/env bash
# Repair the music-AI venvs after a nix-collect-garbage run.
#
# Why this exists: every venv under /zero/ai/music-ai was created with a nix
# python, and `bin/python` is a symlink to that store path. The path has no GC
# root, so `nix-collect-garbage -d` deletes it and the whole venv dies with
# "No such file or directory" — 18 of 20 venvs were down on 2026-10-10. The
# packages inside are fine; only the interpreter link (and the `home` field of
# pyvenv.cfg) has to be re-pointed.
#
# Interpreter order: uv-managed pythons in ~/.local/share/uv/python (they live
# in $HOME and are immune to nix GC), then the system profile. Nothing is
# downloaded; missing interpreters are reported, not installed.
#
# Usage:
#   fix-music-venvs.sh [--root DIR] [--check] [--dry-run] [venv ...]
#
#   --check    report the state and exit non-zero when something is broken
#   --dry-run  print the actions without touching anything
#
# Exit codes: 0 all good (or repaired), 1 something is still broken, 2 bad usage.
set -euo pipefail

ROOT="/zero/ai/music-ai"
MODE="fix"
DRY_RUN=0
SELECTED=()

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      ROOT="${2:?--root needs a directory}"
      shift 2
      ;;
    --check)
      MODE="check"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h | --help) usage 0 ;;
    -*)
      echo "unknown option: $1" >&2
      usage 2
      ;;
    *)
      SELECTED+=("$1")
      shift
      ;;
  esac
done

[[ -d "$ROOT" ]] || {
  echo "no such directory: $ROOT" >&2
  exit 2
}

# "3.12.14" -> "3.12"; a bare "3.11" stays as is.
short_version() {
  local version="$1"
  if [[ "$version" == *.*.* ]]; then
    printf '%s\n' "${version%.*}"
  else
    printf '%s\n' "$version"
  fi
}

# Interpreter for one venv: prefer the uv-managed build of the version the
# venv was created with (it lives in $HOME, so nix GC cannot touch it), then
# the system profile's python3.X.
find_interpreter() {
  local version="$1" short candidate pattern
  short=$(short_version "$version")
  for pattern in "cpython-$version*" "cpython-$short*"; do
    # `find -name` takes the pattern quoted, so shellcheck stays happy and no
    # glob has to survive quoting; `|| true` keeps a miss from tripping -e.
    candidate=$(find "$HOME/.local/share/uv/python" -maxdepth 1 -type d -name "$pattern" 2> /dev/null | sort | tail -1 || true)
    if [[ -n "$candidate" && -x "$candidate/bin/python$short" ]]; then
      printf '%s\n' "$candidate/bin/python$short"
      return 0
    fi
  done
  if [[ -x "/run/current-system/sw/bin/python$short" ]]; then
    printf '%s\n' "/run/current-system/sw/bin/python$short"
    return 0
  fi
  return 1
}

venv_version() {
  local venv="$1" version
  version=$(sed -n 's/^version_info *= *\([0-9.]*\).*/\1/p' "$venv/pyvenv.cfg" 2> /dev/null | head -1)
  if [[ -z "$version" ]]; then
    # Older venvs only record the interpreter path; fall back to its basename.
    version=$(sed -n 's#^home *= *.*python\([0-9]\+\.[0-9]\+\).*#\1#p' "$venv/pyvenv.cfg" 2> /dev/null | head -1)
  fi
  printf '%s\n' "$version"
}

broken=0
fixed=0
skipped=0

mapfile -t venvs < <(find "$ROOT" -maxdepth 1 -type d -name 'venv-*' | sort)
if [[ ${#SELECTED[@]} -gt 0 ]]; then
  filtered=()
  for name in "${SELECTED[@]}"; do
    filtered+=("$ROOT/${name#/}") # accept "venv-x" or an absolute path
  done
  venvs=("${filtered[@]}")
fi

for venv in "${venvs[@]}"; do
  name=$(basename "$venv")
  if [[ ! -f "$venv/pyvenv.cfg" ]]; then
    skipped=$((skipped + 1))
    continue
  fi
  # A venv whose interpreter still resolves needs nothing, whatever its
  # pyvenv.cfg says — several working venvs predate the version_info field.
  current=$(readlink -f "$venv/bin/python" 2> /dev/null || true)
  if [[ -n "$current" && -x "$current" ]]; then
    printf '%-16s ok\n' "$name"
    continue
  fi
  version=$(venv_version "$venv")
  if [[ -z "$version" ]]; then
    # Last resort: the dangling link still carries the version in its name.
    # `|| true`: grep finds nothing on a missing link and pipefail would abort.
    version=$(readlink "$venv/bin/python" 2> /dev/null | grep -o 'python3\.[0-9]*' | head -1 | sed 's/^python//' || true)
  fi
  if [[ -z "$version" ]]; then
    printf '%-16s SKIP  no version in pyvenv.cfg, cannot tell which python it wants\n' "$name"
    skipped=$((skipped + 1))
    continue
  fi
  broken=$((broken + 1))
  if ! interpreter=$(find_interpreter "$version"); then
    printf '%-16s BROKEN %s — no interpreter for this version (uv python install %s)\n' \
      "$name" "$version" "$version"
    continue
  fi
  if [[ "$MODE" == "check" ]]; then
    printf '%-16s BROKEN %s -> would use %s\n' "$name" "$version" "$interpreter"
    continue
  fi
  prefix=$(dirname "$(dirname "$interpreter")")
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%-16s would fix: ln -sfn %s %s/bin/python; pyvenv.cfg home=%s/bin\n' \
      "$name" "$interpreter" "$venv" "$prefix"
    continue
  fi
  ln -sfn "$interpreter" "$venv/bin/python"
  ln -sfn python "$venv/bin/python3"
  ln -sfn python "$venv/bin/python$(short_version "$version")"
  # Pyvenv's `home` locates the stdlib: point it at the interpreter we use.
  if grep -q '^home *=' "$venv/pyvenv.cfg"; then
    sed -i "s#^home *= *.*#home = $prefix/bin#" "$venv/pyvenv.cfg"
  else
    printf 'home = %s/bin\n' "$prefix" >> "$venv/pyvenv.cfg"
  fi
  fixed=$((fixed + 1))
  printf '%-16s FIXED %s -> %s\n' "$name" "$version" "$interpreter"
done

printf '\n%s: %d broken, %d fixed, %d skipped\n' "$ROOT" "$broken" "$fixed" "$skipped"
if [[ "$MODE" == "check" && "$broken" -gt 0 ]]; then
  exit 1
fi
if [[ "$MODE" == "fix" && "$DRY_RUN" == "0" && "$broken" -gt "$fixed" ]]; then
  # Some venv has no interpreter available at all.
  exit 1
fi
exit 0
