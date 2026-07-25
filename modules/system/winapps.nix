{
  lib,
  pkgs,
  config,
  inputs,
  ...
}:
let
  winappsCfg = config.features.apps.winapps or { };
  enabled = winappsCfg.enable or false;
  vmProfile = (config.profiles.vm or { enable = false; }).enable;
in
{
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
      inputs.winapps.packages.${pkgs.stdenv.hostPlatform.system}.winapps # Run Windows apps as native windows
      pkgs.freerdp # RDP client (required for WinApps)
      pkgs.qemu_kvm # QEMU with KVM support
      pkgs.virt-manager # GUI for managing virtual machines
    ];

    # Default winapps config — user can override in ~/.config/winapps/winapps.conf
    environment.etc."winapps/winapps.conf".text = ''
      # WinApps configuration (default)
      # Override in ~/.config/winapps/winapps.conf
      RDP_USER="neg"
      RDP_PASS="neg"
      RDP_DOMAIN=""
      RDP_IP="127.0.0.1"
      RDP_SCALE=100
      MULTIMON="false"
      DEBUG="false"
      RDP_FLAGS="/network:auto /sound:auto /microphone:auto /gfx:avc444 /bpp:32"
    '';
  };
}
