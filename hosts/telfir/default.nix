{ pkgs, ... }:
{

  imports = [
    ./hardware.nix
    ./networking.nix
    ./services.nix
    ./virtualisation/lxc.nix
  ];

  system.preserveFlake = false;
  features.web.enable = true;
  # features.web.floorp.enable = false; # Floorp disabled by default now
  # features.hardware.amdgpu.rocm.enable = false; # ROCm disabled (heavy, unused)
  features.apps.obsidian.enable = true;
  features.mail.vdirsyncer.enable = false;
  features.optimization = {
    enable = true;
  };
  features.net.proxy.enable = true;
  features.net.lan-proxy.enable = true;
  features.net.transparent-proxy.enable = true;
  features.dev.haskell.enable = false; # Disable Haskell toolchain (saves ~1GB)
  features.virt.libvirtd.enable = false; # Disable KVM/QEMU (not needed on this host)
  features.apps.guiAppsFull.enable = false; # Disable heavy GUI apps (GIMP, OBS)
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
