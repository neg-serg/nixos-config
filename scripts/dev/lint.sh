#!/usr/bin/env bash
# The `just lint` suite: every repo gate, run concurrently.
#
# Each gate is one function below; GATES is the ordered table. The gates only
# read the tree, so they run at the same time (bounded by LINT_JOBS, default
# nproc) and their output is captured, then replayed in table order. The report
# reads top-to-bottom like the serial suite it replaces; only the wall time
# changed. A gate that fails does not cancel the others: everything runs, every
# failure is reported, and the exit status is 1 when any gate failed.
#
# Knobs, all environment variables:
#   LINT_JOBS  gates in flight (default nproc)
#   PMAP_JOBS  per-gate fan-out for the checkers that parallelise files
#              (default LINT_JOBS/2, 2..16): the gates already run side by
#              side, so one gate does not get the whole box. Sixteen is the
#              knee on this box — 32 oversubscribes and makes shellcheck slower.
#   LINT_TIMING=1  append each gate's wall time to the report, in table order.
#   LINT_COLOR=always|never  force the colour decision (below); the default is
#              on for a terminal and off for a pipe, and NO_COLOR turns it off.
#   LINT_NO_CACHE=1  lint for real instead of replaying the cached shellcheck
#              verdict (the cache section below explains what the key covers).
#
# Missing tools are a skip with a notice, not a failure — same policy as the
# individual gates; this driver does not decide which tools exist.
#
# Usage: lint.sh [repo-root]
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "${1:-}")"
cd "$REPO_ROOT"

# ── colour ───────────────────────────────────────────────────────────────────
# A gate's output is captured to a file and replayed afterwards, so a tool
# inside it sees a pipe rather than the terminal and drops its colour even when
# the report ends up on one. The decision is therefore made once, here, against
# the suite's own stdout, and the gates receive it as explicit per-tool flags.
# A global FORCE_COLOR is the blunt version of that: it would also recolour
# `nix`, `git` and `just`, whose output some gates parse.
#
# Not every tool can be steered: statix writes SGR codes even into a pipe (it
# honours neither NO_COLOR nor CLICOLOR) and deadnix writes none at all, so
# those two keep whatever they do on their own.
case "${LINT_COLOR:-auto}" in
  always | 1 | yes) colour=1 ;;
  never | 0 | no) colour=0 ;;
  *)
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "${TERM:-}" != "dumb" ]; then
      colour=1
    else
      colour=0
    fi
    ;;
esac

if [ "$colour" -eq 1 ]; then
  c_reset=$'\033[0m' c_dim=$'\033[2m' c_bold=$'\033[1m'
  c_pass=$'\033[1;32m' c_fail=$'\033[1;31m' c_warn=$'\033[1;33m'
  ruff_colour=(--color always)
  taplo_colour=(--colors always)
  selene_colour=(--color Always)
  shellcheck_colour=(--color=always)
else
  c_reset='' c_dim='' c_bold=''
  c_pass='' c_fail='' c_warn=''
  ruff_colour=(--color never)
  taplo_colour=(--colors never)
  selene_colour=(--color Never)
  shellcheck_colour=(--color=never)
fi

LINT_JOBS="${LINT_JOBS:-$(nproc 2> /dev/null || echo 4)}"
if ! [ "$LINT_JOBS" -ge 1 ] 2> /dev/null; then
  LINT_JOBS=$(nproc 2> /dev/null || echo 4)
fi
if [ -z "${PMAP_JOBS:-}" ]; then
  PMAP_JOBS=$((LINT_JOBS / 2))
  [ "$PMAP_JOBS" -ge 2 ] || PMAP_JOBS=2
  [ "$PMAP_JOBS" -le 16 ] || PMAP_JOBS=16
fi
export PMAP_JOBS

# ── the gates ────────────────────────────────────────────────────────────────

gate_nix() {
  statix check -- .
  deadnix --fail .
  # Repo-wide Nix anti-patterns (with-pkgs forms, ExecStart file/dir mutations,
  # bare `with lib`). Rule list and env gates:
  #   bash scripts/dev/lint-guards.sh --list
  bash "$REPO_ROOT/scripts/dev/lint-guards.sh" "$REPO_ROOT"
}

gate_python() {
  # ruff first, then black: under `set -e` a failing ruff aborts the gate, so
  # black's success cannot mask it.
  if git ls-files -- '*.py' > /dev/null 2>&1; then
    ruff check "${ruff_colour[@]}" -- .
    black --check --line-length 79 --extend-exclude files/kitty .
  fi
}

gate_toml() {
  # Tracked files only: a bare `taplo lint` follows result/ into the nix store
  # (pyright's typeshed alone is ~200 METADATA.toml) plus the local nix/ dump,
  # for ~1s of pointless walking. RUST_LOG=warn hides taplo's file-list INFO.
  if command -v taplo > /dev/null 2>&1; then
    git ls-files -z -- '*.toml' 2> /dev/null \
      | RUST_LOG=warn xargs -0 -r taplo lint "${taplo_colour[@]}"
  else
    printf '%s\n' "${c_warn}taplo not found — skipping TOML lint${c_reset}"
  fi
}

gate_rust() {
  # Rust formatting (edition-aware via nearest Cargo.toml)
  if command -v rustfmt > /dev/null 2>&1; then
    bash "$REPO_ROOT/scripts/dev/check-rustfmt.sh"
  else
    printf '%s\n' "${c_warn}rustfmt not found — skipping Rust check${c_reset}"
  fi
}

gate_lua() {
  # Lua (non-nvim; nvim is a vendored config)
  if command -v selene > /dev/null 2>&1; then
    selene "${selene_colour[@]}" files/gui files/mpv
  else
    printf '%s\n' "${c_warn}selene not found — skipping Lua lint${c_reset}"
  fi
}

gate_music() {
  # Music index/similar payloads: offline stub-embedder selftests (no
  # torch/model/venv), skipped with a notice when python3 is missing — same
  # style as the rustfmt/selene gates.
  if command -v python3 > /dev/null 2>&1; then
    just music-selftest
  else
    printf '%s\n' "${c_warn}python3 not found — skipping music payload selftest${c_reset}"
  fi
}

shellcheck_one() {
  shellcheck -S warning -x "${shellcheck_colour[@]}" "$1"
}

# ── shellcheck result cache ──────────────────────────────────────────────────
# The gate's inputs are the repo's shell scripts: their contents, which of them
# exist, the shellcheck version/flags/options, and its rc files. With `-x`
# It follows `source`d paths *statically* — a `$var` target is refused
# (SC1090/SC1091), and the `$(dirname …)/literal` idiom resolves inside the
# repo — so every file it reads is one of those scripts. One key over the whole
# set is therefore exact: a hit cannot report a pass a fresh run would not.
#
# `shellcheck_cache_sources_safe` is what keeps that claim true as the tree
# changes. It walks every `source` line in the set and rejects the run (no
# cache, plain execution) when one could resolve outside it: a literal absolute
# path, a literal target that is not a `*.sh`/`*.bash` file, or the dirname
# idiom whose tail is not one. Dynamic targets need no key — shellcheck will
# not follow them either.
#
# Content-addressed entries are never rewritten, so a stale one is simply never
# looked up again. LINT_NO_CACHE=1 turns the whole thing off.
shellcheck_cache_rc=0
SHELLCHECK_CACHE_DIR=""
if [ "${LINT_NO_CACHE:-0}" != "1" ]; then
  if [ -n "${XDG_CACHE_HOME:-}" ]; then
    SHELLCHECK_CACHE_DIR="$XDG_CACHE_HOME/just-lint/shellcheck"
  elif [ -n "${HOME:-}" ]; then
    SHELLCHECK_CACHE_DIR="$HOME/.cache/just-lint/shellcheck"
  fi
  if [ -n "$SHELLCHECK_CACHE_DIR" ] \
    && ! mkdir -p "$SHELLCHECK_CACHE_DIR" 2> /dev/null; then
    SHELLCHECK_CACHE_DIR=""
  fi
fi

# Return 1 when a `source` line could resolve to a file the key does not hash.
# $@ is the hashed file set.
shellcheck_cache_sources_safe() {
  local line rest word
  local -a words=()
  while IFS= read -r line; do
    rest="${line#"${line%%[![:space:]]*}"}"
    if [ "${rest#\#}" != "$rest" ]; then
      # A directive line: judge the paths it names, not the whole line.
      # `source-path=` widens what `source=` may point at, so it is judged too.
      read -ra words <<< "${rest#\#}"
      for word in "${words[@]}"; do
        case "$word" in
          source-path=*) ;;
          *) continue ;;
        esac
        case "${word#source-path=}" in
          SCRIPTDIR | SRCDIR) ;;
          # Any other search path may leave the repo or follow a variable.
          *'$'* | *'`'* | /* | *..* | '') return 1 ;;
        esac
      done
      for word in "${words[@]}"; do
        case "$word" in
          source=*) shellcheck_cache_target_safe "${word#source=}" || return 1 ;;
        esac
      done
      continue
    fi
    case "$rest" in
      source*) rest="${rest#source}" ;;
      .*) rest="${rest#.}" ;;
    esac
    rest="${rest#"${rest%%[![:space:]]*}"}"
    shellcheck_cache_target_safe "$rest" || return 1
  done < <(
    grep -hE '^[[:space:]]*(\.|source)[[:space:]]|^# shellcheck source' -- "$@" \
      2> /dev/null || true
  )
  return 0
}

# Judge a source expression: 0 when it can only name a file the key hashes (a
# `*.sh`/`*.bash` inside the repo), or when shellcheck cannot resolve it at all
# (a `$var`/backtick target is refused with SC1090/SC1091). 1 when it might
# reach outside the set, which turns the cache off for that run.
shellcheck_cache_target_safe() {
  local expr=$1 target
  case "$expr" in
    # The dirname idiom: shellcheck resolves the literal tail after the last
    # `)`, and that tail is relative to the directory it resolved — so only the
    # name is judged, not the leading slash it starts with.
    *'$('*)
      target="${expr##*)}"
      target="${target#[\"\']}"
      target="${target%%[[:space:]]*}"
      target="${target%[\"\']}"
      case "$target" in
        *.sh | *.bash) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *'$'* | *'`'*) return 0 ;;
  esac
  # First word, unquoted — `./lib.sh "$@"` names ./lib.sh.
  target="${expr#[\"\']}"
  target="${target%%[[:space:]]*}"
  target="${target%[\"\']}"
  case "$target" in
    /*) return 1 ;;
    *.sh | *.bash) return 0 ;;
    *) return 1 ;;
  esac
}

# Print the cache key for the current tree, or nothing (and fail) when the run
# must not be cached.
shellcheck_cache_digest() {
  local -a scripts=()
  local bin file version
  # The exact build, not just its version string: the devshell and the system
  # may ship different derivations of the same upstream release.
  bin=$(command -v shellcheck 2> /dev/null) || return 1
  version=$(shellcheck --version 2> /dev/null | sed -n 's/^version: //p') \
    || return 1
  [ -n "$version" ] || return 1
  while IFS= read -r -d '' file; do
    [ -e "$file" ] && scripts+=("$file")
  done < <(
    git ls-files -z -- '*.sh' '*.bash'
    git ls-files -z --others --exclude-standard -- '*.sh' '*.bash'
  )
  [ "${#scripts[@]}" -gt 0 ] || return 1
  shellcheck_cache_sources_safe "${scripts[@]}" || return 1
  {
    printf 'bin %s\nversion %s\n' "$bin" "$version"
    printf 'args -S warning -x %s\n' "${shellcheck_colour[*]}"
    printf 'opts %s\n' "${SHELLCHECK_OPTS:-}"
    # rc files in the tree and in the user's config dirs change the verdict.
    sha256sum -- .shellcheckrc \
      "${HOME:-/nonexistent}/.shellcheckrc" \
      "${XDG_CONFIG_HOME:-${HOME:-/nonexistent}/.config}/shellcheckrc" \
      2> /dev/null || true
    sha256sum -z -- "${scripts[@]}"
  } | sha256sum | cut -d' ' -f1
}

# Echo the cached log for key $1 and set shellcheck_cache_rc; return 1 on miss.
shellcheck_cache_hit() {
  local entry
  for entry in "$SHELLCHECK_CACHE_DIR/$1"-*.log; do
    [ -e "$entry" ] || return 1
    shellcheck_cache_rc="${entry##*-}"
    shellcheck_cache_rc="${shellcheck_cache_rc%.log}"
    printf '%s\n' "$entry"
    return 0
  done
  return 1
}

# Keys are one per tree state, so the directory only grows. Half of it goes
# when it passes 512 entries: the report never needs an old state to survive.
shellcheck_cache_prune() {
  local -a entries=("$SHELLCHECK_CACHE_DIR"/*.log)
  [ "${#entries[@]}" -gt 512 ] || return 0
  rm -f -- "${entries[@]:0:256}"
}

gate_shellcheck() {
  # Opt-in shell lint: only files that declare a POSIX/Bash shebang. The
  # shebang is read with a builtin — a `grep` per file cost ~0.1 s before the
  # first checker started. One checker process per file: the old single
  # invocation was serial and dominated the suite's wall time.
  local file shebang digest entry rc=0 tmp
  local -a files=() ordered=()
  while IFS= read -r -d '' file; do
    IFS= read -r shebang < "$file" || true
    if [[ $shebang =~ ^#![[:space:]]*/(usr/)?bin/(env[[:space:]]+)?(ba)?sh ]]; then
      files+=("$file")
    fi
  done < <(git ls-files -z -- '*.sh' '*.bash')
  if [ "${#files[@]}" -eq 0 ]; then
    return 0
  fi
  digest=""
  if [ -n "$SHELLCHECK_CACHE_DIR" ]; then
    digest=$(shellcheck_cache_digest) || digest=""
  fi
  if [ -n "$digest" ] && entry=$(shellcheck_cache_hit "$digest"); then
    printf 'shellcheck: %s file(s) (cached)\n' "${#files[@]}"
    cat -- "$entry"
    return "$shellcheck_cache_rc"
  fi
  printf 'shellcheck: %s file(s)\n' "${#files[@]}"
  # Longest first: shellcheck cost tracks file size, and a 1300-line parity
  # harness takes ~0.65 s on its own. Started last in git order, it would hold
  # up the whole gate's tail; started first, the rest fits underneath it.
  # `du`+`sort` are two processes for the whole list.
  while IFS=$'\t' read -r _size file; do
    ordered+=("$file")
  done < <(du -b -- "${files[@]}" | sort -rn)
  # The stored log is the part after the header line above: replaying it gives
  # the same report a fresh run prints below its own header.
  tmp=""
  if [ -n "$digest" ]; then
    tmp=$(mktemp "$SHELLCHECK_CACHE_DIR/.tmp.XXXXXXXX" 2> /dev/null) || tmp=""
  fi
  if [ -z "$tmp" ]; then
    pmap -0 -- shellcheck_one < <(printf '%s\0' "${ordered[@]}")
    return
  fi
  pmap -0 -- shellcheck_one < <(printf '%s\0' "${ordered[@]}") > "$tmp" 2>&1 \
    || rc=$?
  cat -- "$tmp"
  if mv -f -- "$tmp" "$SHELLCHECK_CACHE_DIR/$digest-$rc.log" 2> /dev/null; then
    shellcheck_cache_prune
  else
    rm -f -- "$tmp"
  fi
  return "$rc"
}

gate_plm() {
  bash "$REPO_ROOT/scripts/dev/check-plm.sh" "$REPO_ROOT"
}

gate_scene_events() {
  bash "$REPO_ROOT/scripts/dev/check-scene-events.sh" "$REPO_ROOT"
}

gate_hyprland_vars() {
  bash "$REPO_ROOT/scripts/dev/check-hyprland-vars.sh" "$REPO_ROOT"
}

gate_relative_paths() {
  bash "$REPO_ROOT/scripts/dev/check-relative-paths.sh" "$REPO_ROOT"
}

gate_absolute_home() {
  bash "$REPO_ROOT/scripts/dev/check-absolute-home.sh" "$REPO_ROOT"
}

gate_doc_links() {
  bash "$REPO_ROOT/scripts/dev/check-doc-links.sh" "$REPO_ROOT"
}

gate_markdown_language() {
  bash "$REPO_ROOT/scripts/dev/check-markdown-language.sh"
}

gate_repo_stats() {
  bash "$REPO_ROOT/scripts/dev/repo-stats.sh" --check "$REPO_ROOT"
}

gate_all_syntax() {
  bash "$REPO_ROOT/scripts/dev/check-all-syntax.sh" "$REPO_ROOT"
}

gate_osh_syntax() {
  bash "$REPO_ROOT/scripts/dev/check-osh-syntax.sh" "$REPO_ROOT"
}

gate_lusty_smoke() {
  bash "$REPO_ROOT/scripts/dev/check-lusty-smoke.sh"
}

gate_annotations() {
  bash "$REPO_ROOT/scripts/dev/check-package-annotations.sh" "$REPO_ROOT"
}

# The zsh syntax theme and LS_COLORS are two tables for the same shell; this
# gate keeps them on one palette and on the same colour per extension.
gate_shell_palette() {
  bash "$REPO_ROOT/scripts/dev/check-shell-palette.sh" "$REPO_ROOT"
}

# Ordered gate table. Order is the report order; execution is concurrent.
GATES=(
  nix
  python
  toml
  rust
  lua
  music
  shellcheck
  plm
  scene_events
  hyprland_vars
  relative_paths
  absolute_home
  doc_links
  markdown_language
  repo_stats
  all_syntax
  shell_palette
  osh_syntax
  lusty_smoke
  annotations
)

# ── runner ───────────────────────────────────────────────────────────────────

TMP="$(mktemp -d "${TMPDIR:-/tmp}/lint.XXXXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Launch every gate, keeping at most LINT_JOBS in flight. The exit status is
# written by the subshell, not read with `wait`: the throttle below reaps jobs
# with `wait -n`, and a reaped pid cannot be waited on again.
declare -a pids=()
running=0
for name in "${GATES[@]}"; do
  (
    start=$EPOCHREALTIME
    rc=0
    "gate_$name" || rc=$?
    printf '%s\n' "$rc" > "$TMP/$name.rc"
    printf '%s %s\n' "$start" "$EPOCHREALTIME" > "$TMP/$name.time"
  ) > "$TMP/$name.log" 2>&1 &
  pids+=("$!")
  running=$((running + 1))
  if [ "$running" -ge "$LINT_JOBS" ]; then
    wait -n || true
    running=$((running - 1))
  fi
done

failed=()
for ((i = 0; i < ${#GATES[@]}; i++)); do
  name="${GATES[$i]}"
  wait "${pids[$i]}" 2> /dev/null || true
  rc=$(cat "$TMP/$name.rc" 2> /dev/null || echo 1)
  if [ "$rc" -eq 0 ]; then
    printf '\n%s>>>%s %s%s%s\n' "$c_dim" "$c_reset" "$c_pass" "$name" "$c_reset"
  else
    printf '\n%s>>>%s %s%s (FAILED)%s\n' \
      "$c_dim" "$c_reset" "$c_fail" "$name" "$c_reset"
    failed+=("$name")
  fi
  if [ -s "$TMP/$name.log" ]; then
    cat "$TMP/$name.log"
    if [ -n "$(tail -c 1 "$TMP/$name.log")" ]; then
      printf '\n'
    fi
  fi
done

# Gate wall times, on request: the table order is the report order, so a slow
# gate is found without re-running the suite with tracing.
if [ "${LINT_TIMING:-0}" = 1 ]; then
  printf '%s\n' "${c_bold}lint: gate wall times${c_reset}"
  {
    for name in "${GATES[@]}"; do
      read -r start end < "$TMP/$name.time" 2> /dev/null || continue
      printf '%s %s %s\n' "$name" "$start" "$end"
    done
  } | awk '{ printf "  %-18s %6.2fs\n", $1, $3 - $2 }'
  echo
fi

echo
if [ "${#failed[@]}" -eq 0 ]; then
  printf '%slint: all %s gates passed%s\n' "$c_pass" "${#GATES[@]}" "$c_reset"
  exit 0
fi
printf '%slint: %s of %s gates failed: %s%s\n' \
  "$c_fail" "${#failed[@]}" "${#GATES[@]}" "${failed[*]}" "$c_reset" >&2
exit 1
