{
  lib,
  pkgs,
  ...
}: let
  hasAliae = pkgs ? aliae;
in
  lib.mkMerge [
    # Enable Aliae when available in current nixpkgs
    (lib.mkIf hasAliae (lib.mkMerge [
      {programs.aliae.enable = true;}
      # Provide a cross-shell alias set via XDG config.
      # (xdg.mkXdgText "aliae/config.yaml" aliasContent)
    ]))

    # Soft warning if package is missing
    (lib.mkIf (! hasAliae) {
      warnings = [
        "Aliae is not available in the pinned nixpkgs; skip enabling programs.aliae."
      ];
    })
  ]
