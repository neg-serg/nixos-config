{ config, pkgs, ... }:
let
  onDemand = config.lib.neg.onDemand pkgs;
in
{
  environment.systemPackages = [
    # Git tools
    (onDemand {
      name = "wt";
      attr = "worktrunk";
      binary = "wt";
    }) # git worktree manager: create, switch and clean up worktrees, built on first call
    pkgs.qrencode # QR generator for clipboard helpers
  ];
}
