#!/usr/bin/env bash
# Differential harness for the `derivationStrict` memo, the one patch in
# `packages/nix-eval-patched` that can silently change a `drvPath`: it answers a
# repeated derivation from a hash-keyed memo and, on a hit, returns the cached
# store path *without* re-writing the derivation. Everything else in that stack
# is a cache in front of the store; this one decides what a `drvPath` is.
#
# The claim to validate is "removing the memo changes no result", so the harness
# removes it — in the same binary, with the `eval-memo` setting that our 0006a
# patch adds — and compares what the two runs derive.
#
# Per target, in one binary:
#   1. `$NIX eval --raw <installable>` with the memo enabled (the default) and
#      again with `--option eval-memo false`, each in its own process: the memo
#      lives in the `EvalState`, so two processes are two independent memos.
#      `--no-eval-cache` keeps the flake eval cache out of the measurement, so
#      both runs really evaluate and neither is served from a previous one.
#   2. Compares the two `drvPath` values.
#   3. `$NIX derivation show -r` on each result and compares the whole
#      derivation closure — every `.drv` path in it and each derivation's JSON —
#      canonicalised with `jq -S`, so key order and formatting cannot cause a
#      false difference. The first divergence is reported with its context.
#   4. Counts the memo's own `-vvv` lines (`derivationStrict: memo hit|stored`)
#      to show the switch does something: with the memo enabled the counter must
#      move, with `eval-memo = false` it must stay at zero — the memo structure
#      is then never consulted, never filled, never allocated.
#
# A run that compared identical closures while the memo never hit anywhere is a
# failure (exit 5), not a pass: it would have proven nothing.
#
# What this cannot catch: a difference that is stable across both modes. If the
# memo key is wrong in a way that also mis-keys the un-memoised path, or if both
# runs are wrong in the same direction (e.g. the store already held a stale
# `.drv`), the A/B agrees and says nothing. It also does not compare against a
# Nix *without* the patch stack — for that, build the upstream package and run
# the same corpus with `--nix` pointing at each binary.
#
# Usage: nix-memo-diff.sh [--corpus FILE] [--flake REF] [--attr PATH]
#                          [--nix PATH] [--repeat N] [--verbosity N]
#                          [--keep] [--verbose] [--help]
#   --corpus FILE  one target per line: `REF [ATTR]`
#                    REF   a flake ref — a path (`/etc/nixos`, `.`) or a
#                          registry ref (`nixpkgs`), optionally already carrying
#                          `#attr` (`nixpkgs#hello`)
#                    ATTR  dotted attribute path inside that flake's output,
#                          default `drvPath`; it is appended to REF, so
#                          `nixpkgs#hello drvPath` evaluates
#                          `nixpkgs#hello.drvPath` and `/etc/nixos <path>`
#                          evaluates `/etc/nixos#<path>`
#                  Blank lines and lines whose first non-blank character is `#`
#                  are ignored (`#` inside a line is part of the flake ref).
#                  The corpus checked in beside this script,
#                  `scripts/dev/nix-memo-diff.corpus`, is the host-wide set
#                  (the toplevel plus two nixpkgs leaves); pass it with
#                  `--corpus scripts/dev/nix-memo-diff.corpus`.
#   --flake REF    single-target mode: the flake ref (default /etc/nixos)
#   --attr PATH    single-target mode: the attribute (default: the trantor
#                  toplevel drvPath)
#   --nix PATH     the Nix to test; NIX= in the environment does the same.
#                  Default `nix`, i.e. the system one — point it at the patched
#                  binary, which is what the harness is for:
#                    nix build /etc/nixos#nix-eval-patched -o /tmp/nix-patched
#                    scripts/dev/nix-memo-diff.sh --nix /tmp/nix-patched/bin/nix
#   --repeat N     evaluate each target N times per mode, interleaved, and
#                  report the best (minimum) wall time per mode; every round is
#                  compared, so a non-deterministic result is still caught.
#                  Default 2, because the first evaluation of a dirty flake in
#                  a session also copies the source tree into the store and
#                  fills the page cache: with N=1 that one-off cost lands on
#                  whichever mode runs first and reads as a 2x memo effect.
#   --verbosity N  `-v` count for the evaluation runs (default 3, i.e. `-vvv`),
#                  which is what makes the memo's hit/store lines visible
#   --keep         keep the scratch directory (drvPaths, logs, canonical JSON)
#   --verbose      log the commands and the scratch paths
#
# Env: NIX overrides the binary (same as --nix); TMPDIR places the scratch dir.
# The harness needs a *writable* cache directory for the Nix client it drives
# (XDG_CACHE_HOME or ~/.cache), exactly like any other `nix` invocation.
#
# Exit status:
#   0  every target identical, and the memo demonstrably hit somewhere
#   1  a divergence: drvPath, closure membership or derivation JSON
#   2  usage error
#   3  the binary cannot be used: not executable, or no `eval-memo` setting
#   4  an evaluation or `nix derivation show` failed (nothing was compared)
#   5  everything matched, but the memo never hit: the A/B proved nothing
#   6  the flake's worktree changed while it was being evaluated, so the two
#      runs did not see the same input (a concurrent edit, e.g. another agent)
#
# Example:
#   scripts/dev/nix-memo-diff.sh --nix /tmp/memo-diff-result/bin/nix --repeat 2
set -euo pipefail

LC_ALL=C
export LC_ALL

DEFAULT_FLAKE=/etc/nixos
DEFAULT_ATTR='nixosConfigurations.trantor.config.system.build.toplevel.drvPath'
# The evaluator lines counted as evidence (patch 0006a, lvlDebug).
MEMO_HIT_RE='derivationStrict: memo hit for'
MEMO_STORE_RE='derivationStrict: memo stored for'
INSTANTIATED_RE="^instantiated '"

usage() {
  # Print the header's usage block: from `# Usage:` to the end of the comment block.
  awk '/^# Usage:/ { p = 1 } p && !/^#/ { exit } p { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
}

note() { printf 'nix-memo-diff: %s\n' "$*" >&2; }
debug() {
  if [ "$verbose" -eq 1 ]; then
    note "$*"
  fi
}
usage_error() {
  note "$*"
  usage >&2
  exit 2
}

# ── timing ──────────────────────────────────────────────────────────────────
# EPOCHREALTIME is bash's own clock in seconds with a fractional part; strip the
# separator (LC_ALL=C above) and work in whole microseconds, so a measurement
# costs no fork.
now_us() { printf '%s' "${EPOCHREALTIME/[.,]/}"; }

# $1 = start in µs -> "seconds.milliseconds"
secs_since() {
  local d=$(($(now_us) - $1))
  printf '%d.%03d' $((d / 1000000)) $((d % 1000000 / 1000))
}

# ── counting the evidence ───────────────────────────────────────────────────
# $1 = log file, $2 = regex; prints the match count, 0 when there is no match
# (grep exits 1 then, which would otherwise kill the run under `set -e`).
count_in() {
  local n
  n=$(grep -c -E -- "$2" "$1" 2> /dev/null || true)
  printf '%s' "${n:-0}"
}

flake="$DEFAULT_FLAKE"
attr="$DEFAULT_ATTR"
corpus=""
repeat=2
verbosity=3
keep=0
verbose=0
while [ $# -gt 0 ]; do
  case "$1" in
    --corpus)
      shift
      [ $# -gt 0 ] || usage_error "--corpus needs a file"
      corpus="$1"
      ;;
    --flake)
      shift
      [ $# -gt 0 ] || usage_error "--flake needs a ref"
      flake="$1"
      ;;
    --attr)
      shift
      [ $# -gt 0 ] || usage_error "--attr needs an attribute path"
      attr="$1"
      ;;
    --nix)
      shift
      [ $# -gt 0 ] || usage_error "--nix needs a path"
      NIX="$1"
      ;;
    --repeat)
      shift
      case "${1:-}" in
        '' | *[!0-9]* | 0) usage_error "--repeat needs a positive number" ;;
      esac
      repeat="$1"
      ;;
    --verbosity)
      shift
      case "${1:-}" in
        '' | *[!0-9]*) usage_error "--verbosity needs a number" ;;
      esac
      verbosity="$1"
      ;;
    --keep) keep=1 ;;
    --verbose | -v) verbose=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) usage_error "unknown flag: $1" ;;
    *) usage_error "unexpected argument: $1" ;;
  esac
  shift
done

if [ -n "$corpus" ] && { [ "$flake" != "$DEFAULT_FLAKE" ] || [ "$attr" != "$DEFAULT_ATTR" ]; }; then
  usage_error "--corpus replaces --flake/--attr: put every target in the corpus file"
fi

NIX="${NIX:-nix}"

# ── the binary has to be the patched one ────────────────────────────────────
# The whole point is the switch, so a binary without it is a hard failure and
# not a quiet no-op: `--option eval-memo false` would only warn about an unknown
# setting and then run with the memo on, i.e. compare the memo against itself.
preflight() {
  if ! command -v "$NIX" > /dev/null 2>&1 && [ ! -x "$NIX" ]; then
    note "not an executable Nix: $NIX (use --nix PATH or NIX=...)"
    exit 3
  fi
  debug "binary: $NIX ($("$NIX" --version 2> /dev/null || echo 'version unknown'))"

  local out
  if ! out=$("$NIX" config show 2> /dev/null); then
    note "$($NIX config show) failed; is the store reachable?"
    exit 3
  fi
  if ! printf '%s\n' "$out" | grep -q '^eval-memo = '; then
    note "$NIX has no \`eval-memo\` setting: this is not the patched Nix."
    note "Build it with: nix build /etc/nixos#nix-eval-patched -o /tmp/nix-patched"
    note "  then:        $0 --nix /tmp/nix-patched/bin/nix"
    exit 3
  fi
  if ! printf '%s\n' "$out" | grep -q '^eval-memo = true$'; then
    note "\`eval-memo\` is not enabled by default in $NIX (see \`nix config show\`)"
    note "the memo must be the default for this A/B to mean anything"
    exit 3
  fi
  if ! out=$("$NIX" config show --option eval-memo false 2> /dev/null); then
    note "\`$NIX config show --option eval-memo false\` failed"
    exit 3
  fi
  if ! printf '%s\n' "$out" | grep -q '^eval-memo = false$'; then
    note "the \`eval-memo\` setting of $NIX cannot be turned off"
    exit 3
  fi
}

# ── scratch space ───────────────────────────────────────────────────────────
work=$(mktemp -d "${TMPDIR:-/tmp}/nix-memo-diff.XXXXXX")
cleanup() {
  if [ "$keep" -eq 1 ]; then
    note "scratch kept in $work"
  else
    # Only ever our own mktemp directory, and only after checking it still looks
    # like one — the path is a variable, so a guard is cheaper than a mistake.
    case "$work" in
      "${TMPDIR:-/tmp}"/nix-memo-diff.*) rm -r -- "$work" ;;
    esac
  fi
}
trap cleanup EXIT

# ── targets ─────────────────────────────────────────────────────────────────
# One `ref<TAB>attr` line per target, so single-target mode and corpus mode run
# through exactly the same loop.
targets="$work/targets"
if [ -n "$corpus" ]; then
  [ -r "$corpus" ] || usage_error "cannot read the corpus file: $corpus"
  while IFS= read -r line || [ -n "$line" ]; do
    line=${line#"${line%%[![:space:]]*}"}
    case "$line" in
      '' | '#'*) continue ;;
    esac
    read -r ref rest <<< "$line"
    printf '%s\t%s\n' "$ref" "${rest:-drvPath}" >> "$targets"
  done < "$corpus"
  [ -s "$targets" ] || usage_error "the corpus file has no targets: $corpus"
else
  printf '%s\t%s\n' "$flake" "$attr" > "$targets"
fi

# Append ATTR to REF the way a flake installable spells it.
installable_for() {
  case "$1" in
    *'#'*) printf '%s.%s' "$1" "$2" ;;
    *) printf '%s#%s' "$1" "$2" ;;
  esac
}

# ── is the flake's tree standing still? ─────────────────────────────────────
# A flake directory is an input in full, and /etc/nixos is a dirty worktree that
# other sessions write to: a concurrent edit moves the drvPath and would look
# exactly like a memo bug. Fingerprint HEAD, the worktree status and the content
# of everything git calls modified or untracked, before and after the pair.
# Prints nothing (and returns 1) for a target that is not a local git worktree,
# e.g. `nixpkgs#hello` straight from the registry.
tree_fingerprint() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  git -C "$dir" rev-parse --show-toplevel > /dev/null 2>&1 || return 1
  {
    git -C "$dir" rev-parse HEAD 2> /dev/null
    git -C "$dir" status --porcelain=v2 -z -uall 2> /dev/null | tr '\0' '\n'
    # Paths with a newline in them cannot be expressed to `--stdin-paths`; they
    # are rare enough that the status lines above still move when they change.
    git -C "$dir" ls-files -z -m -o --exclude-standard 2> /dev/null \
      | tr '\0' '\n' | git -C "$dir" hash-object --stdin-paths 2> /dev/null
  } | sha256sum | cut -d' ' -f1
}

# Stop with exit 6: the two runs did not see the same input, so the comparison
# says nothing either way. $1 = fingerprint before, $2 = after, $3 = when.
tree_moved() {
  note "  the flake worktree changed $3 ($1 -> $2),"
  note "  so the two runs did not see the same input: nothing can be concluded."
  note "  Re-run when the tree is quiet — /etc/nixos is a shared worktree."
  exit 6
}

# ── one A/B case ────────────────────────────────────────────────────────────
# Report the first differing derivation of a closure and the JSON context
# around it. Only called on a mismatch, so the extra jq runs are free.
report_json_diff() {
  local dir="$1" line key side
  # Only the differing lines, and only the first of them: `mapfile -n 1` stops
  # reading, and diff's "broken pipe" on the discarded tail is not an error.
  local -a first=()
  mapfile -t -n 1 first < <(
    diff --old-line-format='< %L' --new-line-format='> %L' --unchanged-line-format='' \
      "$dir/off.canon" "$dir/on.canon" 2> /dev/null || true
  )
  line=${first[0]:-}
  case "$line" in
    '< '*) side="only with the memo disabled" ;;
    '> '*) side="only with the memo enabled" ;;
    *) side="unknown side" ;;
  esac
  key=${line:2}
  key=${key%%$'\t'*}
  note "  first differing derivation ($side): $key"
  jq -S --arg k "$key" '.[$k]' "$dir/off.drvs.json" > "$dir/off.one" 2> /dev/null || true
  jq -S --arg k "$key" '.[$k]' "$dir/on.drvs.json" > "$dir/on.one" 2> /dev/null || true
  diff -u --label 'memo off' --label 'memo on' "$dir/off.one" "$dir/on.one" \
    | head -40 | sed 's/^/  /' >&2 || true
}

case_ok=1
total_paths=0
total_hits_on=0

run_case() {
  local label="$1" installable="$2" dir
  dir="$work/$(printf '%s' "${label}${installable}" | tr -c '[:alnum:]' '_')"
  mkdir -p "$dir"
  note "[$label] $installable"

  local round mode opt t0 status
  # `-v` repeated `verbosity` times, or nothing at all: a bare `-` would be read
  # as "evaluate stdin" by `nix eval`.
  local i
  local vflag="no -v"
  local -a vargs=()
  if [ "$verbosity" -gt 0 ]; then
    vflag="-"
    for ((i = 0; i < verbosity; i++)); do vflag="${vflag}v"; done
    vargs=("$vflag")
  fi

  local fp_before fp_after
  fp_before=$(tree_fingerprint "${installable%%#*}" || true)

  local best_on="" best_off=""
  for ((round = 1; round <= repeat; round++)); do
    for mode in on off; do
      opt=true
      [ "$mode" = off ] && opt=false
      t0=$(now_us)
      status=0
      "$NIX" eval --raw --no-eval-cache --option eval-memo "$opt" "${vargs[@]}" \
        "$installable" > "$dir/$mode.drv" 2> "$dir/$mode.log" || status=$?
      local ms
      ms=$(secs_since "$t0")
      if [ "$status" -ne 0 ]; then
        # A worktree that changes mid-evaluation is the most likely cause here
        # (`nix` itself refuses: "files do not change during evaluation"), so
        # say that instead of blaming the memo.
        local fp_now
        fp_now=$(tree_fingerprint "${installable%%#*}" || true)
        if [ -n "$fp_before" ] && [ "$fp_before" != "$fp_now" ]; then
          tree_moved "$fp_before" "$fp_now" "during the memo-$mode run"
        fi
        note "  eval failed with the memo $mode (exit $status):"
        tail -5 "$dir/$mode.log" | sed 's/^/  /' >&2
        exit 4
      fi
      if [ "$mode" = on ]; then
        if [ -z "$best_on" ] || [ "$(printf '%s\n%s\n' "$ms" "$best_on" | sort -n | head -1)" = "$ms" ]; then
          best_on="$ms"
        fi
      else
        if [ -z "$best_off" ] || [ "$(printf '%s\n%s\n' "$ms" "$best_off" | sort -n | head -1)" = "$ms" ]; then
          best_off="$ms"
        fi
      fi
      debug "round $round, memo $mode: ${ms} s"
    done
    if ! cmp -s "$dir/on.drv" "$dir/off.drv"; then
      # A concurrent edit to the flake (another agent, an editor) moves the
      # drvPath and would look exactly like a memo bug, so rule it out first.
      local fp_now
      fp_now=$(tree_fingerprint "${installable%%#*}" || true)
      if [ -n "$fp_before" ] && [ "$fp_before" != "$fp_now" ]; then
        tree_moved "$fp_before" "$fp_now" "between the two runs of round $round"
      fi
      note "  DIVERGENCE on drvPath (round $round):"
      note "    memo on : $(cat "$dir/on.drv")"
      note "    memo off: $(cat "$dir/off.drv")"
      case_ok=0
      return 1
    fi
  done

  fp_after=$(tree_fingerprint "${installable%%#*}" || true)
  if [ -n "$fp_before" ] && [ "$fp_before" != "$fp_after" ]; then
    tree_moved "$fp_before" "$fp_after" "while it was being evaluated"
  fi

  local drvPath
  drvPath=$(cat "$dir/on.drv")

  # The closure behind that drvPath, in both modes.
  for mode in on off; do
    t0=$(now_us)
    status=0
    "$NIX" derivation show -r "$drvPath" > "$dir/$mode.json" 2> "$dir/$mode.show.log" || status=$?
    local ms
    ms=$(secs_since "$t0")
    if [ "$status" -ne 0 ]; then
      note "  \`nix derivation show -r\` failed with the memo $mode (exit $status):"
      tail -5 "$dir/$mode.show.log" | sed 's/^/  /' >&2
      exit 4
    fi
    if [ "$mode" = on ]; then show_on="$ms"; else show_off="$ms"; fi
    # `nix derivation show` wraps the closure as {"version": N, "derivations":
    # {<drv path>: {...}}}; `.derivations // .` keeps this working if that
    # changes back to a flat map. Then one sortable line per derivation:
    # `<drv path>\t<compact canonical JSON>`, so a plain diff finds the first
    # differing derivation.
    jq -S -c '.derivations // .' "$dir/$mode.json" > "$dir/$mode.drvs.json"
    jq -r -S -c 'to_entries | sort_by(.key)[] | "\(.key)\t\(.value)"' \
      "$dir/$mode.drvs.json" > "$dir/$mode.canon"
  done

  local paths_on paths_off
  paths_on=$(jq -r 'keys | length' "$dir/on.drvs.json")
  paths_off=$(jq -r 'keys | length' "$dir/off.drvs.json")

  local hits_on hits_off stored_on stored_off inst_on inst_off
  hits_on=$(count_in "$dir/on.log" "$MEMO_HIT_RE")
  hits_off=$(count_in "$dir/off.log" "$MEMO_HIT_RE")
  stored_on=$(count_in "$dir/on.log" "$MEMO_STORE_RE")
  stored_off=$(count_in "$dir/off.log" "$MEMO_STORE_RE")
  inst_on=$(count_in "$dir/on.log" "$INSTANTIATED_RE")
  inst_off=$(count_in "$dir/off.log" "$INSTANTIATED_RE")

  note "  drvPath : $drvPath"
  note "  eval    : on ${best_on} s / off ${best_off} s (best of $repeat, $vflag)"
  note "  show    : on ${show_on} s / off ${show_off} s"
  note "  memo    : on ${hits_on} hit / ${stored_on} stored; off ${hits_off} hit / ${stored_off} stored"
  note "  instantiated: on ${inst_on} / off ${inst_off}"

  if [ "$paths_on" -ne "$paths_off" ]; then
    note "  DIVERGENCE: the closures differ in size ($paths_on vs $paths_off derivations)"
    report_json_diff "$dir"
    case_ok=0
  elif ! cmp -s "$dir/on.canon" "$dir/off.canon"; then
    note "  DIVERGENCE: the derivation closures differ ($paths_on derivations)"
    report_json_diff "$dir"
    case_ok=0
  fi

  if cmp -s "$dir/on.canon" "$dir/off.canon"; then
    note "  closure : $paths_on derivations, identical ($(wc -c < "$dir/on.canon") bytes of canonical JSON)"
  else
    note "  closure : DIFFERENT"
  fi
  total_paths=$((total_paths + paths_on))
  total_hits_on=$((total_hits_on + hits_on))

  # The switch has to be visible: no memo hit may survive `eval-memo = false`,
  # and the store side must stay silent too — an empty memo writes nothing into
  # itself, so this is the direct check that the bypass bypasses.
  if [ "$hits_off" -ne 0 ] || [ "$stored_off" -ne 0 ]; then
    note "  DIVERGENCE: the memo was used with \`eval-memo = false\`"
    case_ok=0
  fi
  # Same amount of derivationStrict work in both modes; the memo only saves
  # writes, so a different count means the two runs are not comparable.
  if [ "$inst_on" -ne "$inst_off" ]; then
    note "  DIVERGENCE: the runs instantiated a different number of derivations"
    case_ok=0
  fi
  if [ "$inst_on" -eq 0 ]; then
    note "  note: no \`instantiated\` line at $vflag — is the binary built without the"
    note "  note: \`instantiated\` message, or is $verbosity too small?"
  fi
  note "  result  : $([ "$case_ok" -eq 1 ] && echo identical || echo DIFFERENT)"
}

preflight

target_n=0
total_targets=$(wc -l < "$targets")
while IFS=$'\t' read -r ref target_attr; do
  target_n=$((target_n + 1))
  run_case "$target_n/$total_targets" "$(installable_for "$ref" "$target_attr")"
done < "$targets"

note ""
note "$total_targets target(s), $total_paths derivations compared, memo hit $total_hits_on time(s)"
if [ "$case_ok" -ne 1 ]; then
  note "FAIL: the memo changed a result"
  exit 1
fi
if [ "$total_hits_on" -eq 0 ]; then
  note "FAIL: every closure matched, but the memo never hit — this evaluation has no"
  note "      repeated derivation, so the A/B compared the memo with itself. Use a"
  note "      larger target (a NixOS toplevel, not a leaf package) to get evidence."
  exit 5
fi
note "OK: identical drvPaths and derivation closures with the memo on and off"
