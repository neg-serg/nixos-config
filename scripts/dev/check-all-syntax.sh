#!/usr/bin/env bash
# Syntax-check all non-Nix, non-Python, non-shell files in the repo.
# Covers Lua, JavaScript, JSON, JSONC, YAML, TOML, and CSS.
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
check_yaml() { python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$1" 2>&1; }
check_toml() { python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$1" 2>&1; }

# No CSS parser in the devshell; brace balance catches the common error class.
check_css() {
  python3 - "$1" << 'EOF'
import sys
text = open(sys.argv[1]).read()
if text.count('{') != text.count('}'):
    raise ValueError(f"Unbalanced braces: {text.count('{')} open vs {text.count('}')} close")
EOF
}

has_cmd() { command -v "$1" > /dev/null 2>&1; }
has_pyyaml() { python3 -c 'import yaml' 2> /dev/null; }

# Section table: header|guard|guard-arg|checker|count-label|globs|skip-warning
sections=(
  "Lua syntax|has_cmd|luajit|check_lua|Lua|*.lua|luajit not found; skipping Lua syntax check"
  "JavaScript syntax|has_cmd|node|check_js|JavaScript|*.js|node not found; skipping JavaScript syntax check"
  "JSON syntax|has_cmd|jq|check_json|JSON|*.json|jq not found; skipping JSON syntax check"
  "JSONC syntax|has_cmd|jq|check_jsonc|JSONC|*.jsonc|jq not found; skipping JSONC syntax check"
  "YAML syntax|has_pyyaml||check_yaml|YAML|*.yml *.yaml|PyYAML not found; skipping YAML syntax check"
  "TOML syntax|has_cmd|python3|check_toml|TOML|*.toml|python3 not found; skipping TOML syntax check"
  "CSS brace balance|has_cmd|python3|check_css|CSS|*.css|python3 not found; skipping CSS brace check"
)

# Run one section: announce it, skip when the tool is absent, otherwise check
# every tracked match and report the first 5 lines of each failure.
run_section() {
  local header=$1 guard=$2 guard_arg=$3 checker=$4 count_label=$5 globs=$6 warning=$7
  local -a pathspecs
  local count=0 file output
  read -ra pathspecs <<< "$globs"
  echo "Checking $header..."
  if "$guard" "$guard_arg"; then
    while IFS= read -r -d '' file; do
      ((count++)) || true
      if ! output=$("$checker" "$file"); then
        echo "ERROR: $file"
        echo "$output" | head -5
        echo ""
        fail=1
      fi
    done < <(tracked "${pathspecs[@]}")
    echo "Checked $count $count_label file(s)"
  else
    echo "WARNING: $warning" >&2
  fi
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
