{
  lib,
  pkgs,
  config,
  ...
}: let
  winappsCfg = config.features.apps.winapps or {};
  enabled = winappsCfg.enable or false;
  vmProfile = (config.profiles.vm or {enable = false;}).enable;
in {
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = !vmProfile;
        message = "features.apps.winapps.enable is intended for bare-metal hosts; disable profiles.vm.enable when using WinApps.";
      }
      {
        assertion = config.virtualisation.libvirtd.enable or false;
        message = "features.apps.winapps.enable requires KVM/libvirt (virtualisation.libvirtd.enable = true).";
      }
    ];

    # WinApps runtime helpers:
    # - FreeRDP client (xfreerdp) for RDP into the Windows VM
    # - virt-manager / qemu_kvm are typically provided by modules/system/virt.nix,
    #   but kept here as mkAfter to ensure they are present on WinApps hosts.
    environment.systemPackages = lib.mkAfter [
      pkgs.freerdp
      pkgs.virt-manager
      pkgs.qemu_kvm
    ];
  };
}

