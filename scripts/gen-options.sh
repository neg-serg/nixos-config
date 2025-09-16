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

# Determine available systems by inspecting flake packages
systems=$(nix eval --json "$flake_path#packages" | jq -r 'keys[]')
if [[ -z "$systems" ]]; then
  echo "error: no packages.<system> found in flake outputs" >&2
  exit 1
fi

found_system=$(echo "$systems" | head -n1)
if [[ -z "$found_system" ]]; then
  echo "error: failed to detect a system under packages" >&2
  exit 2
fi

echo "Using system: $found_system" >&2

# Discover available options-* docs dynamically
all_keys=$(nix eval --json "$flake_path#packages.${found_system}" | jq -r 'keys[]')
mapfile -t option_keys < <(echo "$all_keys" | awk '/^options-.*-md$|^options-md$/')

# Stable order: index -> aggregated -> the rest sorted
attrs=()
if printf '%s\n' "${option_keys[@]}" | grep -qx 'options-index-md'; then attrs+=(options-index-md); fi
if printf '%s\n' "${option_keys[@]}" | grep -qx 'options-md'; then attrs+=(options-md); fi
rest=$(printf '%s\n' "${option_keys[@]}" | grep -v -E '^options-(index-)?md$' | sort || true)
if [[ -n "$rest" ]]; then
  while IFS= read -r k; do attrs+=("$k"); done <<< "$rest"
fi

if [[ ${#attrs[@]} -eq 0 ]]; then
  echo "error: no options-*-md artifacts found in packages.${found_system}" >&2
  exit 3
fi

for attr in "${attrs[@]}"; do
  case "$attr" in
    options-index-md) out="index.md";;
    options-md) out="options.md";;
    *) out="${attr%-md}.md";;
  esac
  tmp_link="${root_dir}/.result-${attr}"
  rm -f "$tmp_link"
  echo "Building $attr -> $out ..." >&2
  nix build "$flake_path#packages.${found_system}.${attr}" -o "$tmp_link" >/dev/null
  real=$(readlink -f "$tmp_link")
  cp -f "$real" "$docs_dir/$out"
  echo "Wrote $docs_dir/$out" >&2
  rm -f "$tmp_link"
done

echo "Done." >&2
