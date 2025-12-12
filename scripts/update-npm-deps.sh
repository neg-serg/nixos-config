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
  # Clean up node_modules to ensure fresh calculation if needed, 
  # though prefetch-npm-deps usually reads lockfile.
  # rm -rf node_modules 
  
  new_hash=$(prefetch-npm-deps package-lock.json)
  echo "New hash: $new_hash"

  # Update default.nix if it exists
  if [[ -f "default.nix" ]]; then
    # Use sed to replace the hash
    # Pattern looks for: npmDepsHash = "sha256-..."
    sed -i -E "s|npmDepsHash = \"sha256-[^\"]+\";|npmDepsHash = \"$new_hash\";|" default.nix
    echo "Updated default.nix"
  else
    echo "Warning: default.nix not found in $dir. Hash not updated in Nix expression."
  fi

  popd > /dev/null
  echo "Done with $name"
  echo "---------------------------------------------------"
}

# List of packages to maintain
# You can add more directories here as needed
PACKAGES=(
  "packages/mcp/firecrawl"
  "packages/mcp/memory"
  "packages/mcp/ripgrep"
  "packages/mcp/sequentialthinking"
  "packages/mcp/server-filesystem"
  "packages/awrit"
  "home/modules/user/gui/vicinae/extensions/neg-hello"
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
