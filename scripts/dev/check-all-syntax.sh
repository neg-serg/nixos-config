#!/usr/bin/env bash
# Syntax-check all non-Nix, non-Python, non-shell files in the repo.
# Covers Lua, JavaScript, JSON, JSONC, YAML, TOML, and CSS.
# Each section discovers files via `git ls-files`, skips gracefully when the
# required tool is missing, and reports every failure before exiting non-zero.

set -euo pipefail

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2> /dev/null || pwd)}"
cd "$REPO_ROOT"

fail=0

# --- Lua ---------------------------------------------------------------
echo "Checking Lua syntax..."
if command -v luajit > /dev/null 2>&1; then
  lua_count=0
  while IFS= read -r -d '' file; do
    ((lua_count++)) || true
    # -b compiles to bytecode without executing; -l lists it (sent to /dev/null).
    # Syntax errors land on stderr and make the command fail.
    if ! output=$(luajit -bl "$file" 2>&1 > /dev/null); then
      echo "ERROR: $file"
      echo "$output" | head -5
      echo ""
      fail=1
    fi
  done < <(git ls-files -z -- '*.lua')
  echo "Checked $lua_count Lua file(s)"
else
  echo "WARNING: luajit not found; skipping Lua syntax check" >&2
fi

# --- JavaScript --------------------------------------------------------
echo "Checking JavaScript syntax..."
if command -v node > /dev/null 2>&1; then
  js_count=0
  while IFS= read -r -d '' file; do
    ((js_count++)) || true
    # QML JavaScript modules start with `.pragma library` (Qt Quick directive),
    # which node does not parse; strip those lines before checking.
    # ESM files (top-level import/export, e.g. dsh plugin host halves) fail a
    # plain CJS stdin check; pass --input-type=module when one is detected.
    input_type=commonjs
    if grep -qE '^(import|export)[[:space:]]' "$file"; then
      input_type=module
    fi
    if ! output=$(sed '/^\.pragma/d' "$file" | node --input-type="$input_type" --check - 2>&1); then
      echo "ERROR: $file"
      echo "$output" | head -5
      echo ""
      fail=1
    fi
  done < <(git ls-files -z -- '*.js')
  echo "Checked $js_count JavaScript file(s)"
else
  echo "WARNING: node not found; skipping JavaScript syntax check" >&2
fi

# --- JSON --------------------------------------------------------------
echo "Checking JSON syntax..."
if command -v jq > /dev/null 2>&1; then
  json_count=0
  while IFS= read -r -d '' file; do
    ((json_count++)) || true
    if ! output=$(jq . "$file" 2>&1 > /dev/null); then
      echo "ERROR: $file"
      echo "$output" | head -5
      echo ""
      fail=1
    fi
  done < <(git ls-files -z -- '*.json')
  echo "Checked $json_count JSON file(s)"
else
  echo "WARNING: jq not found; skipping JSON syntax check" >&2
fi

# --- JSONC -------------------------------------------------------------
# JSONC files may contain whole-line // comments and /* */ blocks.
# Only line-anchored comments are stripped, so // inside strings (e.g. URLs)
# is preserved.
echo "Checking JSONC syntax..."
if command -v jq > /dev/null 2>&1; then
  jsonc_count=0
  while IFS= read -r -d '' file; do
    ((jsonc_count++)) || true
    if ! output=$(sed -e '/^[[:space:]]*\/\//d' -e '/^[[:space:]]*\/\*/,/^[[:space:]]*\*\//d' "$file" | jq . 2>&1 > /dev/null); then
      echo "ERROR: $file"
      echo "$output" | head -5
      echo ""
      fail=1
    fi
  done < <(git ls-files -z -- '*.jsonc')
  echo "Checked $jsonc_count JSONC file(s)"
else
  echo "WARNING: jq not found; skipping JSONC syntax check" >&2
fi

# --- YAML --------------------------------------------------------------
echo "Checking YAML syntax..."
if python3 -c 'import yaml' 2> /dev/null; then
  yaml_count=0
  while IFS= read -r -d '' file; do
    ((yaml_count++)) || true
    if ! output=$(python3 -c 'import sys, yaml; yaml.safe_load(open(sys.argv[1]))' "$file" 2>&1); then
      echo "ERROR: $file"
      echo "$output" | head -5
      echo ""
      fail=1
    fi
  done < <(git ls-files -z -- '*.yml' '*.yaml')
  echo "Checked $yaml_count YAML file(s)"
else
  echo "WARNING: PyYAML not found; skipping YAML syntax check" >&2
fi

# --- TOML --------------------------------------------------------------
echo "Checking TOML syntax..."
if command -v python3 > /dev/null 2>&1; then
  toml_count=0
  while IFS= read -r -d '' file; do
    ((toml_count++)) || true
    if ! output=$(python3 -c 'import sys, tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$file" 2>&1); then
      echo "ERROR: $file"
      echo "$output" | head -5
      echo ""
      fail=1
    fi
  done < <(git ls-files -z -- '*.toml')
  echo "Checked $toml_count TOML file(s)"
else
  echo "WARNING: python3 not found; skipping TOML syntax check" >&2
fi

# --- CSS ---------------------------------------------------------------
# No CSS parser in the devshell; brace balance catches the common error class.
echo "Checking CSS brace balance..."
if command -v python3 > /dev/null 2>&1; then
  css_count=0
  while IFS= read -r -d '' file; do
    ((css_count++)) || true
    if ! output=$(
      python3 - "$file" << 'EOF'
import sys
text = open(sys.argv[1]).read()
if text.count('{') != text.count('}'):
    raise ValueError(f"Unbalanced braces: {text.count('{')} open vs {text.count('}')} close")
EOF
    ); then
      echo "ERROR: $file"
      echo "$output" | head -5
      echo ""
      fail=1
    fi
  done < <(git ls-files -z -- '*.css')
  echo "Checked $css_count CSS file(s)"
else
  echo "WARNING: python3 not found; skipping CSS brace check" >&2
fi

echo ""
if [[ $fail -ne 0 ]]; then
  echo "FAILED: syntax errors found (see above)"
  exit 1
fi
echo "All additional syntax checks passed!"
