#!/usr/bin/env bash
# Syntax-check all non-Nix, non-Python, non-shell files in the repo.
# Covers Lua/Luau, JavaScript, JSON, JSONC, YAML, TOML, and CSS.
# Each section discovers files via `git ls-files`, skips gracefully when the
# required tool is missing, and reports every failure before exiting non-zero.

set -euo pipefail

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"
REPO_ROOT="$(repo_root "${1:-}")"
cd "$REPO_ROOT"

# Git-tracked files matching the given pathspecs that still exist on disk. A
# file deleted in the working tree but not yet staged is still in the index;
# handing it to a checker aborts the run with a misleading FileNotFoundError.
tracked() {
  git ls-files -z -- "$@" | while IFS= read -r -d '' file; do
    [ -e "$file" ] && printf '%s\0' "$file"
  done
}

fail=0

# --- per-language checkers (file path in $1; diagnostics on stdout) --------
# luajit -b compiles to bytecode without executing; -l lists it (sent to
# /dev/null). Syntax errors land on stderr and make the command fail.
check_lua() { { luajit -bl "$1" > /dev/null; } 2>&1; }

# QML JavaScript modules start with `.pragma library` (Qt Quick directive),
# which node does not parse; strip those lines before checking. ESM files
# (top-level import/export, e.g. dsh plugin host halves) fail a plain CJS stdin
# check; pass --input-type=module when one is detected.
check_js() {
  local input_type=commonjs
  if grep -qE '^(import|export)[[:space:]]' "$1"; then
    input_type=module
  fi
  sed '/^\.pragma/d' "$1" | node --input-type="$input_type" --check - 2>&1
}

# JSONC files may contain whole-line // comments and /* */ blocks. Only
# line-anchored comments are stripped, so // inside strings (e.g. URLs) is
# preserved.
check_json() { { jq . "$1" > /dev/null; } 2>&1; }
check_jsonc() { { sed -e '/^[[:space:]]*\/\//d' -e '/^[[:space:]]*\/\*/,/^[[:space:]]*\*\//d' "$1" | jq . > /dev/null; } 2>&1; }

# One python3 process for a whole section. A python startup and import per file
# cost ~11 ms × 139 files, more than the parsers themselves; the checks are the
# same ones, only the loop moved inside. Failures print in file order, in the
# same shape as `syntax_one` (header, up to five diagnostic lines, blank).
# The YAML/TOML parsers are PyYAML and the stdlib tomllib; the CSS "parser" is
# the brace-balance check no devshell tool covers.
batch_check() {
  local mode=$1
  shift
  python3 - "$mode" "$@" << 'EOF'
import sys

mode, paths = sys.argv[1], sys.argv[2:]
failed = False
for path in paths:
    try:
        if mode == "yaml":
            import yaml

            with open(path) as fh:
                yaml.safe_load(fh)
        elif mode == "toml":
            import tomllib

            with open(path, "rb") as fh:
                tomllib.load(fh)
        else:  # css brace balance
            with open(path) as fh:
                text = fh.read()
            if text.count("{") != text.count("}"):
                raise ValueError(
                    f"Unbalanced braces: {text.count('{')} open vs {text.count('}')} close"
                )
    except Exception as exc:
        failed = True
        print(f"ERROR: {path}")
        for line in str(exc).splitlines()[:5]:
            print(line)
        print()
sys.exit(1 if failed else 0)
EOF
}

batch_yaml() { batch_check yaml "$@"; }
batch_toml() { batch_check toml "$@"; }
batch_css() { batch_check css "$@"; }

has_cmd() { command -v "$1" > /dev/null 2>&1; }
has_pyyaml() { python3 -c 'import yaml' 2> /dev/null; }

# Section table: header|guard|guard-arg|checker|count-label|globs|skip-warning
#
# pleamar's scene logic (*.luau) is kept Lua 5.1-compatible so the same luajit
# parse covers it. This is the only gate that sees a logic syntax error:
# `pleamar --check` compiles the .plm alone, and a broken logic file leaves its
# scene running with no handlers at all (measured: the panels scene died on a
# `...` in a closure while every gate stayed green).
sections=(
  "Lua syntax|has_cmd|luajit|check_lua|Lua|*.lua *.luau|luajit not found; skipping Lua syntax check"
  "JavaScript syntax|has_cmd|node|check_js|JavaScript|*.js|node not found; skipping JavaScript syntax check"
  "JSON syntax|has_cmd|jq|check_json|JSON|*.json|jq not found; skipping JSON syntax check"
  "JSONC syntax|has_cmd|jq|check_jsonc|JSONC|*.jsonc|jq not found; skipping JSONC syntax check"
  "YAML syntax|has_pyyaml||batch_yaml|YAML|*.yml *.yaml|PyYAML not found; skipping YAML syntax check"
  "TOML syntax|has_cmd|python3|batch_toml|TOML|*.toml|python3 not found; skipping TOML syntax check"
  "CSS brace balance|has_cmd|python3|batch_css|CSS|*.css|python3 not found; skipping CSS brace check"
)

# Worker for pmap: check one file with the checker of the current section and
# print its diagnostics only when it fails. pmap replays these blocks in input
# order, so the report reads exactly like the serial loop this replaced.
syntax_one() {
  local file=$1 output
  if ! output=$("$SYNTAX_CHECKER" "$file"); then
    printf 'ERROR: %s\n' "$file"
    printf '%s\n' "$output" | head -5
    printf '\n'
    return 1
  fi
}

# Run one section: announce it, skip when the tool is absent, otherwise check
# every tracked match concurrently (one process per file, bounded by pmap) and
# report the first 5 lines of each failure. Checkers named `batch_*` take the
# whole file list in one process instead — cheaper than a startup per file for
# the sections a single interpreter can loop over.
run_section() {
  local header=$1 guard=$2 guard_arg=$3 checker=$4 count_label=$5 globs=$6 warning=$7
  local -a pathspecs
  local -a files=()
  local file
  read -ra pathspecs <<< "$globs"
  echo "Checking $header..."
  if ! "$guard" "$guard_arg"; then
    echo "WARNING: $warning" >&2
    return 0
  fi
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(tracked "${pathspecs[@]}")
  if [ "${#files[@]}" -gt 0 ]; then
    case "$checker" in
      batch_*) "$checker" "${files[@]}" || fail=1 ;;
      *)
        SYNTAX_CHECKER="$checker"
        if ! pmap -0 -- syntax_one < <(printf '%s\0' "${files[@]}"); then
          fail=1
        fi
        ;;
    esac
  fi
  echo "Checked ${#files[@]} $count_label file(s)"
}

for section in "${sections[@]}"; do
  IFS='|' read -r header guard guard_arg checker count_label globs warning <<< "$section"
  run_section "$header" "$guard" "$guard_arg" "$checker" "$count_label" "$globs" "$warning"
done

echo ""
if [[ $fail -ne 0 ]]; then
  echo "FAILED: syntax errors found (see above)"
  exit 1
fi
echo "All additional syntax checks passed!"
