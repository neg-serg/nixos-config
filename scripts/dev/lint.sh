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
# Two knobs, both for a loaded or small machine:
#   LINT_JOBS  gates in flight (default nproc)
#   PMAP_JOBS  per-gate fan-out for the checkers that parallelise files
#              (default LINT_JOBS/2, 2..16): the gates already run side by
#              side, so one gate does not get the whole box. Sixteen is the
#              knee on this box — 32 oversubscribes and makes shellcheck slower.
#   LINT_TIMING=1  append each gate's wall time to the report, in table order.
#
# Missing tools are a skip with a notice, not a failure — same policy as the
# individual gates; this driver does not decide which tools exist.
#
# Usage: lint.sh [repo-root]
set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "${1:-}")"
cd "$REPO_ROOT"

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
    ruff check -- .
    black --check --line-length 79 --extend-exclude files/kitty .
  fi
}

gate_toml() {
  # Tracked files only: a bare `taplo lint` follows result/ into the nix store
  # (pyright's typeshed alone is ~200 METADATA.toml) plus the local nix/ dump,
  # for ~1s of pointless walking. RUST_LOG=warn hides taplo's file-list INFO.
  if command -v taplo > /dev/null 2>&1; then
    git ls-files -z -- '*.toml' 2> /dev/null | RUST_LOG=warn xargs -0 -r taplo lint
  else
    echo "taplo not found — skipping TOML lint"
  fi
}

gate_rust() {
  # Rust formatting (edition-aware via nearest Cargo.toml)
  if command -v rustfmt > /dev/null 2>&1; then
    bash "$REPO_ROOT/scripts/dev/check-rustfmt.sh"
  else
    echo "rustfmt not found — skipping Rust check"
  fi
}

gate_lua() {
  # Lua (non-nvim; nvim is a vendored config)
  if command -v selene > /dev/null 2>&1; then
    selene files/gui files/mpv
  else
    echo "selene not found — skipping Lua lint"
  fi
}

gate_music() {
  # Music index/similar payloads: offline stub-embedder selftests (no
  # torch/model/venv), skipped with a notice when python3 is missing — same
  # style as the rustfmt/selene gates.
  if command -v python3 > /dev/null 2>&1; then
    just music-selftest
  else
    echo "python3 not found — skipping music payload selftest"
  fi
}

shellcheck_one() {
  shellcheck -S warning -x "$1"
}

gate_shellcheck() {
  # Opt-in shell lint: only files that declare a POSIX/Bash shebang. One
  # checker process per file — the old single invocation was serial and
  # dominated the suite's wall time.
  local file
  local -a files=()
  while IFS= read -r -d '' file; do
    if grep -qE '^#!\s*/(usr/)?bin/(env\s+)?(ba)?sh' "$file"; then
      files+=("$file")
    fi
  done < <(git ls-files -z -- '*.sh' '*.bash')
  if [ "${#files[@]}" -eq 0 ]; then
    return 0
  fi
  echo "shellcheck: ${#files[@]} file(s)"
  pmap -0 -- shellcheck_one < <(printf '%s\0' "${files[@]}")
}

gate_plm() {
  bash "$REPO_ROOT/scripts/dev/check-plm.sh" "$REPO_ROOT"
}

gate_scene_events() {
  bash "$REPO_ROOT/scripts/dev/check-scene-events.sh" "$REPO_ROOT"
}

gate_plugin_sandbox() {
  bash "$REPO_ROOT/scripts/dev/check-plugin-sandbox.sh" "$REPO_ROOT"
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
  plugin_sandbox
  hyprland_vars
  relative_paths
  absolute_home
  doc_links
  markdown_language
  repo_stats
  all_syntax
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
    printf '\n>>> %s\n' "$name"
  else
    printf '\n>>> %s (FAILED)\n' "$name"
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
  echo "lint: gate wall times"
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
  echo "lint: all ${#GATES[@]} gates passed"
  exit 0
fi
echo "lint: ${#failed[@]} of ${#GATES[@]} gates failed: ${failed[*]}" >&2
exit 1
