{
  pkgs,
  profile,
  repoRoot ? null,
  flakePath ? null,
  backupFiles ? [ ],
}:
let
  lib = pkgs.lib;
  repoRootLiteral = if repoRoot != null then lib.escapeShellArg repoRoot else ''"$HOME/zaneyos"'';
  flakePathLiteral =
    if flakePath != null then lib.escapeShellArg flakePath else ''"$REPO_ROOT/flake.nix"'';
  backupItems = lib.concatStringsSep " " (map lib.escapeShellArg backupFiles);
in
pkgs.writeShellScriptBin "zcli" ''
  #!/usr/bin/env bash
  set -euo pipefail

  PROFILE=${lib.escapeShellArg profile}
  REPO_ROOT=${repoRootLiteral}
  FLAKE_NIX_PATH=${flakePathLiteral}
  BACKUP_FILES=(${backupItems})

  NH_BIN=${lib.escapeShellArg "${pkgs.nh}/bin/nh"} # Yet another nix cli helper
  GIT_BIN=${lib.escapeShellArg "${pkgs.git}/bin/git"} # Distributed version control system
  INXI_BIN=${lib.escapeShellArg "${pkgs.inxi}/bin/inxi"} # Full featured CLI system information tool
  LSPCI_BIN=${lib.escapeShellArg "${pkgs.pciutils}/bin/lspci"} # Collection of programs for inspecting and manipulating co...
  FIND_BIN=${lib.escapeShellArg "${pkgs.findutils}/bin/find"} # GNU Find Utilities, the basic directory searching utiliti...
  NIX_BIN=${lib.escapeShellArg "${pkgs.nix}/bin/nix"} # Nix package manager
  REALPATH_BIN=${lib.escapeShellArg "${pkgs.coreutils}/bin/realpath"} # GNU Core Utilities
  LSBLK_BIN=${lib.escapeShellArg "${pkgs.util-linux}/bin/lsblk"} # Set of system utilities for Linux

  usage() {
    cat <<USAGE
  zcli - helper for NixOS flake at \$REPO_ROOT

  Commands:
    switch [-- ...]   Run nh os switch for \$PROFILE (default)
    home [-- ...]     Run nh home switch for \$PROFILE
    update            Run nix flake update in \$REPO_ROOT
    status            git status -sb in \$REPO_ROOT
    pull              git pull --rebase in \$REPO_ROOT
    info              Show hardware summary (inxi, lspci, lsblk)
    backups           Report configured backup files under \$HOME
    help              Show this message
  USAGE
  }

  ensure_repo() {
    if [ -z "$REPO_ROOT" ]; then
      echo "REPO_ROOT is not set; update zcli.nix to point at your flake." >&2
      exit 1
    fi
    REPO_ROOT="$($REALPATH_BIN "$REPO_ROOT")"
    if [ ! -d "$REPO_ROOT" ]; then
      echo "Repository path '$REPO_ROOT' does not exist." >&2
      exit 1
    fi
  }

  ensure_flake() {
    ensure_repo
    if [ -e "$FLAKE_NIX_PATH" ]; then
      FLAKE_NIX_PATH="$($REALPATH_BIN "$FLAKE_NIX_PATH")"
      return
    fi

    alt="$($FIND_BIN "$REPO_ROOT" -maxdepth 2 -name flake.nix | head -n 1)"
    if [ -n "$alt" ]; then
      FLAKE_NIX_PATH="$($REALPATH_BIN "$alt")"
      echo "Discovered flake at $FLAKE_NIX_PATH"
    else
      echo "flake.nix not found under $REPO_ROOT" >&2
      exit 1
    fi
  }

  cmd_switch() {
    shift || true
    ensure_flake
    exec "$NH_BIN" os switch --hostname "$PROFILE" --flake "$FLAKE_NIX_PATH" "$@"
  }

  cmd_home() {
    shift || true
    ensure_flake
    exec "$NH_BIN" home switch --hostname "$PROFILE" --flake "$FLAKE_NIX_PATH" "$@"
  }

  cmd_update() {
    shift || true
    ensure_repo
    cd "$REPO_ROOT"
    "$NIX_BIN" flake update "$@"
  }

  cmd_status() {
    shift || true
    ensure_repo
    "$GIT_BIN" -C "$REPO_ROOT" status -sb
  }

  cmd_pull() {
    shift || true
    ensure_repo
    "$GIT_BIN" -C "$REPO_ROOT" pull --rebase
  }

  cmd_info() {
    shift || true
    "$INXI_BIN" -Fazy
    echo
    "$LSPCI_BIN" -nn
    echo
    "$LSBLK_BIN" -f
  }

  cmd_backups() {
    shift || true
    if [ ''${#BACKUP_FILES[@]} -eq 0 ]; then
      echo "No backup files configured; set backupFiles in the zcli module if you need them."
      return
    fi

    for rel in "''${BACKUP_FILES[@]}"; do
      target="$HOME/$rel"
      if [ -e "$target" ]; then
        echo "present: $target"
      else
        echo "missing: $target"
      fi
    done
  }

  case "''${1:-switch}" in
    switch) cmd_switch "$@";;
    home) cmd_home "$@";;
    update) cmd_update "$@";;
    status) cmd_status "$@";;
    pull) cmd_pull "$@";;
    info) cmd_info "$@";;
    backups) cmd_backups "$@";;
    help|-h|--help)
      usage
      ;;
    *)
      echo "Unknown command: ''${1:-}" >&2
      usage
      exit 1
      ;;
  esac
''
