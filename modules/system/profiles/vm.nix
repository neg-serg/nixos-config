##
# Module: system/profiles/vm
# Purpose: VM profile — simpler kernel/packages and disable Secure Boot by default.
# Key options: cfg = config.profiles.vm.enable
# Dependencies: Affects boot.*; complements hosts/*/vm/*.nix.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.profiles.vm or { enable = false; };
in
{
  options.profiles.vm.enable = lib.mkEnableOption "VM profile: prefer generic kernel and trim heavy defaults.";

  config = lib.mkIf cfg.enable {
    boot = {
      # Prefer generic latest kernel; avoid OOT patches in VMs by default
      kernelPatches = lib.mkDefault [ ];
      extraModulePackages = lib.mkDefault [ ];
      kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;
      # Secure Boot stack generally unnecessary in throwaway VMs
      lanzaboote.enable = lib.mkDefault false;
    };
  };
}
