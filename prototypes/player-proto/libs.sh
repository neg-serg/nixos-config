#!/usr/bin/env bash
# Print the library path a nix-wrapped Vulkan app would get for free.
#
# Two traps this script exists to avoid:
#   * NixOS has no ld.so.cache, and winit/ash dlopen libwayland-client, libxkbcommon and
#     libvulkan by soname.
#   * vulkaninfo's RUNPATH also lists glibc and gcc: putting those on LD_LIBRARY_PATH breaks
#     unrelated binaries (rustup cargo dies with "__pointer_chk_guard, version GLIBC_PRIVATE"),
#     so they are filtered out.
set -euo pipefail
dirs=()
while IFS= read -r dir; do
  case "$dir" in
    *-glibc-*|*-gcc-*) continue ;;
  esac
  [ -n "$dir" ] && dirs+=("$dir")
done < <(readelf -d /run/current-system/sw/bin/vulkaninfo | sed -n 's/.*RUNPATH.*\[\(.*\)\]/\1/p' | tr ':' '\n')

# libxkbcommon is dlopened by winit but is not in vulkaninfo's RUNPATH; the store also holds a
# 32-bit copy, which fails with ELFCLASS32.
while IFS= read -r cand; do
  if file -L "$cand" | rg -q 'ELF 64-bit'; then
    dirs+=("$(dirname "$cand")")
    break
  fi
done < <(fd -t l -d 3 '^libxkbcommon\.so\.0$' /nix/store 2>/dev/null)

IFS=':' ; echo "${dirs[*]}"
