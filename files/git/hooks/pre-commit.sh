#!/usr/bin/env bash
set -euo pipefail
# Repo root configured in HM (defaults to /etc/nixos/home)
if [ -n "${config_repo:-}" ]; then
  repo="$config_repo"
else
  repo="/etc/nixos/home"
fi
if [ ! -d "$repo" ]; then
  echo "Home Manager repo '$repo' is missing" >&2
  exit 1
fi
# Run flake checks for HM (format docs, evals, etc.)
(cd "$repo" && nix flake check -L)
# Format via the main repo formatter to keep configs in sync
if [[ "$repo" == */nix/.config/home-manager ]]; then
  repo_root="$(cd "$repo/../.." && pwd)"
else
  repo_root="$(cd "$repo/.." && pwd)"
fi
(cd "$repo_root" && nix fmt)
# Sanity: reject whitespace errors in staged diff
git diff --check
# Stage any formatter changes
git add -u
