#!/usr/bin/env bash
set -euo pipefail

root_dir=${1:-}
if [[ -z "${root_dir}" ]]; then
  if git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
    root_dir="$git_root"
  else
    root_dir="$(pwd)"
  fi
fi

flake_path="$root_dir"
docs_dir="$root_dir/docs"
mkdir -p "$docs_dir"

if [[ ! -f "$root_dir/flake.nix" ]]; then
  echo "error: flake.nix not found in $root_dir" >&2
  exit 1
fi

attr_list=(options-md options-servers-md options-profiles-md options-hardware-md options-all-md)
out_files=(options.md options-servers.md options-profiles.md options-hardware.md options-all.md)

# Determine available systems by inspecting flake packages
systems=$(nix eval --json "$flake_path#packages" | jq -r 'keys[]')
if [[ -z "$systems" ]]; then
  echo "error: no packages.<system> found in flake outputs" >&2
  exit 1
fi

found_system=""
for sys in $systems; do
  if nix eval --json "$flake_path#packages.${sys}" >/dev/null 2>&1; then
    if nix eval --json "$flake_path#packages.${sys}" | jq -e '."options-md"' >/dev/null 2>&1; then
      found_system="$sys"
      break
    fi
  fi
done

if [[ -z "$found_system" ]]; then
  echo "error: options-md package not available; ensure nixosOptionsDoc is supported in your nixpkgs" >&2
  exit 2
fi

echo "Using system: $found_system" >&2

for i in "${!attr_list[@]}"; do
  attr=${attr_list[$i]}
  out=${out_files[$i]}
  if nix eval --json "$flake_path#packages.${found_system}" | jq -e ".\"${attr}\"" >/dev/null 2>&1; then
    tmp_link="${root_dir}/.result-${attr}"
    rm -f "$tmp_link"
    echo "Building $attr ..." >&2
    nix build "$flake_path#packages.${found_system}.${attr}" -o "$tmp_link" >/dev/null
    # Resolve symlink and copy
    real=$(readlink -f "$tmp_link")
    cp -f "$real" "$docs_dir/$out"
    echo "Wrote $docs_dir/$out" >&2
    rm -f "$tmp_link"
  else
    echo "skip: $attr not present for $found_system" >&2
  fi
done

echo "Done." >&2

