#!/usr/bin/env bash
# Compile GLSL to SPIR-V. glslc comes from the shaderc package in the store.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
glslc=${GLSLC:-$(fd -t f -d 3 '^glslc$' /nix/store --max-results 1)}
for f in "$here"/*.vert "$here"/*.frag; do
  "$glslc" --target-env=vulkan1.2 -O -o "${f}.spv" "$f"
done
ls -l "$here"/*.spv
