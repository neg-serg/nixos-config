#!/usr/bin/env bash
# Format or check Rust files with the edition from their nearest Cargo.toml.
# Run without args to check, with --fix to format in place.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "${1:-}")"
MODE="${2:-check}"

cd "$REPO_ROOT"

# The edition of a file comes from the nearest Cargo.toml above it. The walk uses
# parameter expansion and no per-directory grep|sed|tr chain: those subprocesses
# were a visible share of the gate's wall time. It also ends at the repository
# root instead of spinning on `dirname .` (which maps back to itself) when no
# Cargo.toml exists.
edition_for() {
  local dir="${1%/*}" line
  case "$1" in
    */*) ;;
    *) dir="." ;;
  esac
  while :; do
    if [ -f "$dir/Cargo.toml" ]; then
      line="$(grep -m1 '^edition' "$dir/Cargo.toml" 2> /dev/null)" || true
      line="${line#*\"}"
      line="${line%\"*}"
      printf '%s\n' "${line// /}"
      return 0
    fi
    [ "$dir" = "." ] && break
    case "$dir" in
      */*) dir="${dir%/*}" ;;
      *) dir="." ;;
    esac
  done
  echo "2021"
}

# LD_LIBRARY_PATH on this host carries the nix gcc/glibc (pulled in for the GPU
# and AI stacks); the rustup toolchain shim resolves its own libc against that
# value and dies with `undefined symbol: __pointer_chk_guard, version
# GLIBC_PRIVATE`, which the check then reads as "not formatted". Drop the
# variable for rustfmt so the gate reports formatting, not the loader.
#
# The edition depends on the directory only, so it is resolved once per
# directory (the walk up to the nearest Cargo.toml) and once per file kept in
# EDITION. rustfmt takes many files per process, and one process per file was
# almost all startup: 424 files → ~40 ms each. The files are grouped by edition
# (the flag is global) and cut into CHUNK-file lists that pmap runs concurrently.
declare -A DIR_EDITION=()
declare -A EDITION=()
files=()
while IFS= read -r f; do
  files+=("$f")
  case "$f" in
    */*) dir="${f%/*}" ;;
    *) dir="." ;;
  esac
  if [ -z "${DIR_EDITION[$dir]+set}" ]; then
    DIR_EDITION[$dir]="$(edition_for "$f")"
  fi
  EDITION[$f]="${DIR_EDITION[$dir]}"
done < <(git ls-files '*.rs')

if [ "${#files[@]}" -eq 0 ]; then
  exit 0
fi

CHUNK=64
WORK="$(mktemp -d "${TMPDIR:-/tmp}/rustfmt.XXXXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# One list file per (edition, chunk): the worker reads the edition from the file
# name, so it needs no shared map. Sorted by edition first — a chunk may hold
# files of one edition only.
declare -a CHUNKS=()
cur_list=""
cur_edition=""
count=0
id=0
while IFS=$'\t' read -r edition f; do
  if [ -z "$cur_list" ] || [ "$edition" != "$cur_edition" ] || [ "$count" -ge "$CHUNK" ]; then
    cur_edition="$edition"
    id=$((id + 1))
    cur_list="$WORK/$edition-$id.list"
    : > "$cur_list"
    CHUNKS+=("$cur_list")
    count=0
  fi
  printf '%s\n' "$f" >> "$cur_list"
  count=$((count + 1))
done < <(
  for f in "${files[@]}"; do
    printf '%s\t%s\n' "${EDITION[$f]}" "$f"
  done | sort -t $'\t' -k1,1
)

# Worker for pmap: one rustfmt invocation per chunk. A failing chunk re-checks
# its files one by one only to name the offenders — the green path never pays
# for the per-file startup.
rustfmt_chunk() {
  local list="$1" edition chunk f bad=0
  edition="${list##*/}"
  edition="${edition%%-*}"
  mapfile -t chunk < "$list"
  if [ "$MODE" = "fix" ]; then
    env -u LD_LIBRARY_PATH rustfmt --edition "$edition" "${chunk[@]}"
    return 0
  fi
  if env -u LD_LIBRARY_PATH rustfmt --check --edition "$edition" "${chunk[@]}" > /dev/null 2>&1; then
    return 0
  fi
  for f in "${chunk[@]}"; do
    if ! env -u LD_LIBRARY_PATH rustfmt --check --edition "$edition" "$f" > /dev/null 2>&1; then
      echo "rustfmt: $f (edition $edition) not formatted — run 'just rustfmt'"
      bad=1
    fi
  done
  return "$bad"
}

fail=0
if ! pmap -- rustfmt_chunk < <(printf '%s\n' "${CHUNKS[@]}"); then
  fail=1
fi

exit $fail
