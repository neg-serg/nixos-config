#!/usr/bin/env bash
# Eval-time regression guard for the trantor toplevel drvPath.
#
# Measures a plain `nix eval --raw .#…toplevel.drvPath` N times on a clean
# worktree and compares the median with the committed baseline. This is the
# number an agent pays after editing any `.nix` file, and the one that moves
# when modules are added (dendritic/import-tree) or the system closure changes.
# `nixos-eval-gate.sh` is a memo, not a measurement.
#
# A dirty worktree is refused: Nix copies it to the store on every content
# change (measured on a 201 MB clone: +1.2 s warm, +4.3 s with a cold fetch
# cache), which would be blamed on eval.
#
# Usage: eval-bench.sh [--runs N] [--host NAME] [--attr PATH]
#                      [--baseline FILE] [--max-regression PCT]
#                      [--write-baseline] [--allow-dirty]
# Exit status: 0 within the threshold, 1 over it, 2 usage/setup error.
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

ROOT="$(repo_root)"
cd "$ROOT"

runs=5
host=trantor
attr="config.system.build.toplevel.drvPath"
baseline_file="$ROOT/scripts/dev/eval-bench.baseline"
max_pct=15
write_baseline=0
allow_dirty=0

die() {
  printf 'eval-bench: %s\n' "$*" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --runs)
      shift
      runs="${1:?--runs needs a number}"
      ;;
    --host)
      shift
      host="${1:?--host needs a name}"
      ;;
    --attr)
      shift
      attr="${1:?--attr needs a path}"
      ;;
    --baseline)
      shift
      baseline_file="${1:?--baseline needs a file}"
      ;;
    --max-regression)
      shift
      max_pct="${1:?--max-regression needs a percentage}"
      ;;
    --write-baseline) write_baseline=1 ;;
    --allow-dirty) allow_dirty=1 ;;
    -h | --help)
      sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) die "unknown argument: $1 (see --help)" ;;
  esac
  shift
done

case "$runs" in '' | *[!0-9]*) die "--runs must be a positive integer" ;; esac
[ "$runs" -ge 1 ] || die "--runs must be a positive integer"
case "$max_pct" in '' | *[!0-9]*) die "--max-regression must be a non-negative integer" ;; esac

# Untracked files count too: the flake source copy includes them.
if [ -n "$(git status --porcelain)" ]; then
  if [ "$allow_dirty" -eq 1 ]; then
    printf 'eval-bench: WARNING worktree is dirty (dirty-tree copy adds ~1.2 s)\n' >&2
  else
    die "worktree is dirty; commit or stash first (or pass --allow-dirty)"
  fi
fi

head_before="$(git rev-parse --short HEAD)"
# `--option eval-cache false`: the eval cache is not a hit for this attr, so
# disabling it removes a variable without changing the real result.
cmd=(nix eval --raw --option eval-cache false ".#nixosConfigurations.$host.$attr")

tmp="$(mktemp -d "${TMPDIR:-/tmp}/eval-bench.XXXXXXXX")"
cleanup() {
  case "$tmp" in "${TMPDIR:-/tmp}"/eval-bench.*) rm -rf -- "$tmp" ;; esac
}
trap cleanup EXIT

printf 'eval-bench: host=%s head=%s runs=%d attr=%s\n' "$host" "$head_before" "$runs" "$attr"

if command -v hyperfine > /dev/null 2>&1; then
  hyperfine --warmup 1 --runs "$runs" --export-json "$tmp/bench.json" "${cmd[*]}" > /dev/null
  read -r median min max < <(jq -r '.results[0].summary.time_wall_clock | "\(.median) \(.min) \(.max)"' "$tmp/bench.json")
else
  times=()
  for i in $(seq 1 $((runs + 1))); do
    start="${EPOCHREALTIME/./}"
    "${cmd[@]}" > /dev/null
    end="${EPOCHREALTIME/./}"
    [ "$i" -eq 1 ] && continue
    times+=($(((end - start) / 1000)))
  done
  read -r median min max < <(printf '%s\n' "${times[@]}" | sort -n | awk '
    { a[NR] = $1 }
    END {
      m = (NR % 2) ? a[(NR + 1) / 2] : (a[NR / 2] + a[NR / 2 + 1]) / 2
      printf "%.3f %.3f %.3f", m / 1000, a[1] / 1000, a[NR] / 1000
    }')
fi

head_after="$(git rev-parse --short HEAD)"
[ "$head_before" = "$head_after" ] || die "HEAD moved during the benchmark ($head_before -> $head_after); rerun"

printf '  median %.3f s   min %.3f s   max %.3f s\n' "$median" "$min" "$max"

if [ "$write_baseline" -eq 1 ]; then
  printf '%s %s %s\n' "$median" "$head_before" "$(date +%F)" > "$baseline_file"
  printf '  wrote baseline %s: median %s s at %s\n' "$baseline_file" "$median" "$head_before"
  exit 0
fi

[ -f "$baseline_file" ] || die "no baseline at $baseline_file; create one with --write-baseline"
read -r base_median base_head base_date < "$baseline_file"
case "$base_median" in '' | *[!0-9.]*) die "malformed baseline: $baseline_file" ;; esac

pct="$(awk -v m="$median" -v b="$base_median" 'BEGIN { printf "%+.1f", (m / b - 1) * 100 }')"
limit="$(awk -v b="$base_median" -v p="$max_pct" 'BEGIN { printf "%.3f", b * (1 + p / 100) }')"
printf '  baseline %.3f s (%s, %s)   limit %.3f s (+%s%%)\n' "$base_median" "$base_head" "$base_date" "$limit" "$max_pct"
printf '  delta %s%%\n' "$pct"

if awk -v m="$median" -v b="$base_median" -v p="$max_pct" 'BEGIN { exit !(m > b * (1 + p / 100)) }'; then
  printf 'eval-bench: FAIL median %.3f s is above %.3f s (+%s%%)\n' "$median" "$limit" "$max_pct" >&2
  exit 1
fi
printf 'eval-bench: PASS\n'
