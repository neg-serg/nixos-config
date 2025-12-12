#!/usr/bin/env bash
set -euo pipefail

# This script automates the update of npm dependencies for Nix packages
# defined in this repository. It performs the following steps for each target:
# 1. Updates package-lock.json with `npm update` (or `npm audit fix`)
# 2. Computes the new npmDepsHash using `prefetch-npm-deps`
# 3. Updates the default.nix file with the new hash

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Ensure prefetch-npm-deps is available
if ! command -v prefetch-npm-deps &> /dev/null; then
  echo "Error: prefetch-npm-deps not found. Please enter a nix-shell -p prefetch-npm-deps or enable it in your devShell."
  echo "Try running: nix-shell -p prefetch-npm-deps --run ./scripts/update-npm-deps.sh"
  exit 1
fi

update_package() {
  local dir="$1"
  local name="$2"

  echo "== Updating $name ($dir) =="
  pushd "$dir" > /dev/null

  # Check if package-lock.json exists
  if [[ ! -f "package-lock.json" ]]; then
    echo "Warning: No package-lock.json found in $dir. Skipping."
    popd > /dev/null
    return
  fi

  # Run npm update
  if [[ -n "${FORCE_AUDIT:-}" ]]; then
      echo "Running npm audit fix --force..."
      npm audit fix --force || true
  else
      echo "Running npm update..."
      npm update
  fi
  
  # Compute new hash
  echo "Computing new npmDepsHash..."

  # Capture output/error to handle failure gracefully
  if new_hash=$(prefetch-npm-deps package-lock.json 2>&1); then
      # Check if output actually looks like a hash (sha256-...)
      # Sometimes prefetch-npm-deps outputs text even on success/warning
      # We extract the last line usually
      new_hash=$(echo "$new_hash" | tail -n1)
      
      if [[ "$new_hash" == sha256-* ]]; then
          echo "New hash: $new_hash"
          # Update default.nix if it exists
          if [[ -f "default.nix" ]]; then
            sed -i -E "s|npmDepsHash = \"sha256-[^\"]+\";|npmDepsHash = \"$new_hash\";|" default.nix
            echo "Updated default.nix"
          else
             echo "Warning: default.nix not found in $dir."
          fi
      else
          echo "Error computing hash: $new_hash"
      fi
  else
      echo "Failed to compute hash for $name"
      echo "Output: $new_hash"
  fi

  popd > /dev/null
  echo "Done with $name"
  echo "---------------------------------------------------"
}

# List of packages to maintain
# You can add more directories here as needed
PACKAGES=(
  # "packages/mcp/firecrawl" # Broken lockfile v3 / npm audit upstream issues
  # "packages/mcp/memory" # Issues with npm audit and prefetch-npm-deps
  # "packages/mcp/ripgrep"
  # "packages/mcp/sequentialthinking" # Broken lockfile v3 / npm audit upstream issues
  # "packages/mcp/server-filesystem"
  # "packages/awrit" # npm error code ENOTCACHED (napi-rs/cli)
  # "home/modules/user/gui/vicinae/extensions/neg-hello"
)

# Main loop
for pkg in "${PACKAGES[@]}"; do
  if [[ -d "$pkg" ]]; then
    update_package "$pkg" "$pkg"
  else
    echo "Directory $pkg not found. Skipping."
  fi
done

echo "All updates complete. Please verify changes with 'git diff' and run 'nix build' to test."
