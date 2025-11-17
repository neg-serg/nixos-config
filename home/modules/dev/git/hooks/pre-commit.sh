#!/usr/bin/env bash
set -euo pipefail
# Repo root configured in HM (dotfilesRoot)
repo="${config_repo:-$HOME/.dotfiles}/nix/.config/home-manager"
# Run flake checks for HM (format docs, evals, etc.)
(cd "$repo" && nix flake check -L)
# Format via the main repo formatter to keep configs in sync
repo_root="$(cd "$repo/../.." && pwd)"
(cd "$repo_root" && nix fmt)
# Sanity: reject whitespace errors in staged diff
git diff --check
# Stage any formatter changes
git add -u
