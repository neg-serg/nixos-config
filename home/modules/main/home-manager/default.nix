{
  lib,
  config,
  ...
}: let
  # Avoid referencing config.lib.neg here to prevent HM eval recursion
  mkLocalBin = import ../../../../packages/lib/local-bin.nix {inherit lib;};
  hmFlakePath = lib.escapeShellArg config.neg.hmConfigRoot;
in
  lib.mkMerge [
    {
      programs.home-manager.enable = true; # Let Home Manager install and manage itself.
    }
    # Small wrapper used by backupCommand: moves the existing path to path.$HOME_MANAGER_BACKUP_EXT
    (mkLocalBin "hm-backup" ''      #!/usr/bin/env bash
       set -euo pipefail

       src="$1"
       if [ -z "$src" ]; then
         echo "usage: hm-backup <path>" >&2
         exit 2
       fi

       ext="$HOME_MANAGER_BACKUP_EXT"
       if [ -z "$ext" ]; then
         ext="bck"
       fi

       dst="$src.$ext"

       # Avoid clobbering: append timestamp if destination exists
       if [ -e "$dst" ] || [ -L "$dst" ]; then
         ts=$(date +%Y%m%d-%H%M%S)
         dst="$src.$ext.$ts"
       fi

       mv -- "$src" "$dst"
    '')
    # Cross-shell helper: fast Home Manager switch for this repo
    (mkLocalBin "seh" ''      #!/usr/bin/env bash
       set -euo pipefail

       # Default backup extension matches repo conventions
       backup_ext="''${HOME_MANAGER_BACKUP_EXT:-bck}"

       # Switch using this repo's flake; pass through any extra args
       exec home-manager -b "''${backup_ext}" switch -j 32 --cores 32 --flake ${hmFlakePath} "$@"
    '')
  ]
