{ config, pkgs, ... }:
let
  onDemand = import (config.lib.neg.path "lib/on-demand-app.nix") {
    inherit pkgs;
    nix = config.nix.package;
  };
in
{
  environment.systemPackages = [
    # Git tools
    (onDemand {
      name = "wt";
      attr = "worktrunk";
      binary = "wt";
    }) # git worktree manager: create, switch and clean up worktrees, built on first call

    # Encoding & hashing
    pkgs.qrencode # QR generator for clipboard helpers

    # Fetch/info tools
    pkgs.fastfetch # modern ASCII system summary
  ];
}
