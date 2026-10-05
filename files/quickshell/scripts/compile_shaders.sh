#!/usr/bin/env zsh
set -euo pipefail

# Compile every .frag shader in ../shaders and ../greeter/shaders to .qsb using
# Qt 6 Shader Tools (qsb). The greeter tree has its own set (glass card, avatar
# disc, CRT pass, wallpaper posterisation) — same tool, same flags.
# Requires: qsb (Qt 6 Shader Tools)

here=${0:h:A}
shader_dirs=(
  "${here:A}/../shaders"
  "${here:A}/../greeter/shaders"
)

if ! command -v qsb > /dev/null 2>&1; then
  echo "Error: 'qsb' not found. Install Qt 6 Shader Tools (qt6-shadertools)." >&2
  exit 1
fi

setopt nullglob
rc=0
for dir in "${shader_dirs[@]}"; do
  for src in "$dir"/*.frag; do
    out="${src}.qsb"
    echo "Compiling ${src#$here/} -> ${out#$here/}"
    # Use a conservative flag set for broader qsb compatibility
    if ! qsb --glsl "100es,120,150" -o "$out" "$src"; then
      echo "Failed to compile: $src" >&2
      rc=1
    fi
  done
done
exit "$rc"
