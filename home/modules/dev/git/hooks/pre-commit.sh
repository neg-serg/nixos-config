#!/usr/bin/env bash
set -euo pipefail
# Repo root configured in HM (dotfilesRoot)
if [ -n "${config_repo:-}" ]; then
  repo="$config_repo"
else
  if [ -d /etc/nixos/home ]; then
    repo="/etc/nixos/home"
  else
    repo="$HOME/.dotfiles/nix/.config/home-manager"
  fi
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
