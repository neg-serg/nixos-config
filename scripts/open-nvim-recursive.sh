#!/usr/bin/env bash
set -euo pipefail

# Recursively collect files under a directory and open them in Neovim.
# Usage: open-nvim-recursive.sh [root-dir] [--name pattern] [--help]

usage() {
  cat <<'EOF'
Usage: open-nvim-recursive.sh [root-dir] [--name pattern]

Options:
  root-dir        Root to scan (default: current directory)
  --name pattern  Find pattern passed to 'find -name' (default: *)
  -h, --help      Show this help

Environment:
  NVIM_BIN        Override nvim binary (default: nvim)
EOF
}

nvim_bin="${NVIM_BIN:-nvim}"
root="."
name_pattern="*"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)
      [[ $# -lt 2 ]] && { echo "Missing value for --name" >&2; exit 1; }
      name_pattern="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      root="$1"
      shift
      ;;
  esac
done

if ! command -v "$nvim_bin" >/dev/null 2>&1; then
  echo "Neovim binary not found: $nvim_bin" >&2
  exit 1
fi

if [[ ! -d "$root" ]]; then
  echo "Root is not a directory: $root" >&2
  exit 1
fi

mapfile -d '' files < <(find "$root" -type f -name "$name_pattern" -print0)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "No files found under '$root' matching '$name_pattern'" >&2
  exit 1
fi

exec "$nvim_bin" "${files[@]}"
