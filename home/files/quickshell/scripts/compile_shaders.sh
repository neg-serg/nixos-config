#!/usr/bin/env bash
set -euo pipefail

# Compile all .frag shaders in ../shaders to .qsb using Qt 6 shadertool (qsb).
# Requires: qsb (Qt 6 Shader Tools)

here="$(cd "$(dirname "$0")" && pwd)"
shaders_dir="$(cd "$here/../shaders" && pwd)"

if ! command -v qsb >/dev/null 2>&1; then
  echo "Error: 'qsb' not found. Install Qt 6 Shader Tools (qt6-shadertools)." >&2
  exit 1
fi

shopt -s nullglob
rc=0
for src in "$shaders_dir"/*.frag; do
  out="${src}.qsb"
  echo "Compiling $(basename "$src") -> $(basename "$out")"
  # Use a conservative flag set for broader qsb compatibility
  if ! qsb --glsl "100es,120,150" -o "$out" "$src"; then
    echo "Failed to compile: $src" >&2
    rc=1
  fi
done
exit "$rc"
