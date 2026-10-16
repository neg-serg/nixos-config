#!/usr/bin/env bash
# Rollout benchmark: how long does one tiny change take to roll out — through
# `nix` and through `fix`?
#
# Every measured round rewrites `system.nixos.label` in hosts/trantor/default.nix
# (the counterpart line is the trigger), so a round performs a real, minimal
# rollout instead of hitting a fully warm no-op. Each engine gets its own label
# value: the store is shared, and the second engine would otherwise find the
# first engine's freshly built derivations already present.
#
# One command per round is measured, because that is the unit a rollout costs:
#
#   nix  nix build <flake>#<toplevel>                 (build the host toplevel)
#   fix  fix build --flake <flake>#<toplevel>         (`fix switch build` target)
#
# Splitting the command into an "evaluate" and a "build" phase is deliberately
# not attempted: `nix` caches evaluation between invocations (eval-cache), while
# `fix` re-evaluates inside every command, so a split would measure the caches
# rather than the rollout. Activation is out of scope as well —
# `switch-to-configuration` requires root and would switch the running system;
# time that with the normal path (`just agent-switch`, `nh os switch`).
#
# Usage: scripts/dev/rollout-bench.sh [--runs N] [--engines fix,nix]
#                                    [--host trantor] [--flake DIR]
#                                    [--csv PATH] [--keep] [--no-warmup]
#
# Every measured round is appended to `--csv` (default
# $XDG_STATE_HOME/rollout-bench.csv, i.e. outside the repository) as
# `timestamp,engine,seconds,host,rev` — one line per round, so runs over time can
# be plotted. Pass `--csv /dev/null` to skip the log.
#
# The `fix` engine needs the binary on PATH (or FIX_BIN=/path/to/fix); build it
# with `nix build .#fix --option substitute false`. Set FIX_XDG_CACHE_HOME to
# give fix its own fetch cache (see below). Note that fix fetches its flake
# inputs itself: the `determinate-nixd` file input lives behind an S3 endpoint
# that stalls from this host, so the first run may need
# `https_proxy=socks5h://127.0.0.1:10808` in the environment.
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
host=trantor
flake=$repo_root
runs=3
engines=fix,nix
keep=0
warmup=1
csv=${XDG_STATE_HOME:-$HOME/.local/state}/rollout-bench.csv

while [ $# -gt 0 ]; do
  case $1 in
    --runs)
      runs=$2
      shift 2
      ;;
    --engines)
      engines=$2
      shift 2
      ;;
    --host)
      host=$2
      shift 2
      ;;
    --flake)
      flake=$2
      shift 2
      ;;
    --csv)
      csv=$2
      shift 2
      ;;
    --keep)
      keep=1
      shift
      ;;
    --no-warmup)
      warmup=0
      shift
      ;;
    -h | --help)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
      exit 0
      ;;
    *)
      echo "rollout-bench: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

label_file=$repo_root/hosts/trantor/default.nix
toplevel="nixosConfigurations.$host.config.system.build.toplevel"
fix_bin=${FIX_BIN:-fix}
nix_opts=(--option substitute false)

have() { command -v "$1" > /dev/null 2>&1; }
have sd || {
  echo "rollout-bench: sd (search-and-replace) is required to bump the label" >&2
  exit 1
}
if [[ $engines == *fix* ]] && ! have "$fix_bin"; then
  echo "rollout-bench: '$fix_bin' not found; build .#fix or pass FIX_BIN=/path/to/fix" >&2
  exit 1
fi

original_label=$(rg -N -o 'system\.nixos\.label = "[^"]*";' "$label_file" | head -1)
if [ -z "$original_label" ]; then
  echo "rollout-bench: no system.nixos.label trigger found in $label_file" >&2
  exit 1
fi

set_label() {
  sd 'system\.nixos\.label = "[^"]*";' "system.nixos.label = \"$1\";" "$label_file"
}

restore_label() {
  if [ "$keep" = 1 ]; then return 0; fi
  sd 'system\.nixos\.label = "[^"]*";' "$original_label" "$label_file"
}
trap restore_label EXIT

now() { date +%s.%N; }
since() { awk -v a="$1" -v b="$2" 'BEGIN { printf "%.2f", b - a }'; }

# `fix` keeps its fetch cache under $XDG_CACHE_HOME/fix. Set FIX_XDG_CACHE_HOME to
# give it its own cache without handing that directory to `nix` as well (nix
# would then lose its fetcher cache and re-download every input).
fix_env=()
if [ -n "${FIX_XDG_CACHE_HOME:-}" ]; then
  fix_env=(
    env
    "XDG_CACHE_HOME=$FIX_XDG_CACHE_HOME"
    "XDG_STATE_HOME=${FIX_XDG_STATE_HOME:-$FIX_XDG_CACHE_HOME}"
    "XDG_DATA_HOME=${FIX_XDG_DATA_HOME:-$FIX_XDG_CACHE_HOME}"
  )
fi

rollout_cmd() {
  case $1 in
    nix)
      nix build --no-link "${nix_opts[@]}" "$flake#$toplevel" > /dev/null
      ;;
    fix)
      "${fix_env[@]}" "$fix_bin" build --no-out-link --flake "$flake#$toplevel" "${nix_opts[@]}" > /dev/null
      ;;
  esac
}

round() { # $1 = engine, $2 = label, $3 = measure (1/0)
  local engine=$1 label=$2 measure=$3
  set_label "$label"
  local t0 t1
  t0=$(now)
  rollout_cmd "$engine"
  t1=$(now)
  if [ "$measure" = 1 ]; then
    printf '%s %s\n' "$engine" "$(since "$t0" "$t1")"
  fi
}

IFS=, read -ra engine_list <<< "$engines"
if [ "$warmup" = 1 ]; then
  echo "warm-up (fetches, daemon connections, first build of a changed label)..." >&2
  for engine in "${engine_list[@]}"; do
    round "$engine" "bench-warmup-$engine" 0
  done
fi

results=$(mktemp)
trap 'rm -f "$results"; restore_label' EXIT
for run in $(seq 1 "$runs"); do
  for engine in "${engine_list[@]}"; do
    echo "run $run/$runs: $engine" >&2
    round "$engine" "bench-$engine-$run" 1 >> "$results"
  done
done

median() { # stdin: numbers
  sort -n | awk '
    { v[NR] = $1 }
    END {
      if (NR == 0) exit
      m = (NR % 2) ? v[(NR + 1) / 2] : (v[NR / 2] + v[NR / 2 + 1]) / 2
      printf "%.2f", m
    }'
}

printf '%-6s %5s %10s\n' engine run rollout
awk '{ printf "%-6s %5d %9ss\n", $1, ++n[$1], $2 }' "$results"
echo
echo "medians"
for engine in "${engine_list[@]}"; do
  printf '  %-4s rollout %ss\n' "$engine" "$(awk -v e="$engine" '$1 == e { print $2 }' "$results" | median)"
done

if [ -n "$csv" ]; then
  mkdir -p "$(dirname "$csv")"
  if [ ! -s "$csv" ]; then
    printf 'timestamp,engine,seconds,host,rev\n' >> "$csv"
  fi
  rev=$(git -C "$repo_root" describe --always --dirty)
  while read -r engine seconds; do
    printf '%s,%s,%s,%s,%s\n' "$(date -Is)" "$engine" "$seconds" "$host" "$rev" >> "$csv"
  done < "$results"
  echo
  echo "appended $(rg -c '' "$results") rows to $csv"
fi
