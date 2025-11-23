##
# Module: servers/wakapi
# Purpose: Wakapi CLI tools profile.
# Key options: cfg = config.servicesProfiles.wakapi.enable
# Dependencies: pkgs.wakapi (CLI).
{
  lib,
  config,
  ...
}: let
  cfg = config.servicesProfiles.wakapi or {enable = false;};
in {
  imports = [./pkgs.nix];
  config = lib.mkIf cfg.enable {
    # Packages moved to ./pkgs.nix
  };
}

