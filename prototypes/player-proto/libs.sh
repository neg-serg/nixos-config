#!/usr/bin/env bash
# Print the LD_LIBRARY_PATH a nix-wrapped Vulkan app would get.
# Discovery is slow (fd + file over the store), so callers cache the result.
set -euo pipefail
libs=$(readelf -d /run/current-system/sw/bin/vulkaninfo | sed -n 's/.*RUNPATH.*\[\(.*\)\]/\1/p')
while IFS= read -r cand; do
  if file -L "$cand" | rg -q 'ELF 64-bit'; then
    libs="$libs:$(dirname "$cand")"
    break
  fi
done < <(fd -t l -d 3 '^libxkbcommon\.so\.0$' /nix/store 2>/dev/null)
printf '%s' "$libs"
