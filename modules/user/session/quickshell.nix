{
  inputs,
  lib,
  pkgs,
  ...
}: let
  mkQuickshellWrapper = import (inputs.self + "/lib/quickshell-wrapper.nix") {
    inherit lib pkgs;
  };
  quickshellPkg = pkgs.quickshell; # use system package to match Qt version
  quickshellWrapped = mkQuickshellWrapper {qsPkg = quickshellPkg;};
in {
  environment.systemPackages = [
    # -- Quickshell --
    quickshellWrapped # wrapped quickshell binary with required envs
  ];
}
