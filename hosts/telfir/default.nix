{ pkgs, ... }:
{

  imports = [
    ./hardware.nix
    ./networking.nix
    ./services.nix
    ./virtualisation/lxc.nix
  ];

  system.preserveFlake = false;
  # Composable profiles: order matters, last wins on conflicts
  features.profiles = [ "desktop" "dev" "gaming" ];

  # Host-specific overrides (above profile defaults)
  features.apps.obsidian.enable = true;
  features.mail.vdirsyncer.enable = false;
  features.net.proxy.enable = true;
  features.net.lan-proxy.enable = true;
  features.net.transparent-proxy.enable = true;
  features.dev.haskell.enable = false; # Disable Haskell toolchain (saves ~1GB)
  features.virt.libvirtd.enable = false; # Disable KVM/QEMU (not needed on this host)
  features.apps.guiAppsFull.enable = false; # Disable heavy GUI apps (GIMP, OBS); gaming profile enables it by default
  features.dev.cpp.enable = true; # Enable C++ toolchain (ccache, gcc, cmake)
  boot.plymouth = {
    enable = true;
    theme = "black_hud";
    themePackages = [
      (pkgs.adi1090x-plymouth-themes.override {
        selected_themes = [ "black_hud" ];
      })
    ];
  };
}
