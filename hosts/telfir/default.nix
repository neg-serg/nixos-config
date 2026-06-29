{ pkgs, ... }:
{
  imports = [
    ./hardware.nix
    ./networking.nix
    ./services.nix
    # ./virtualisation/macos.nix  # Archived - MacOS VM not currently in use
    ./virtualisation/lxc.nix
  ];

  system.preserveFlake = false;

  features.cachyos.enable = true;

  features.web.enable = true;
  features.web.floorp.enable = false;

  features.hardware.amdgpu.rocm.enable = true;
  features.mail.vdirsyncer.enable = false;

  # Optimization settings
  features.optimization = {
    enable = true;
  };

  features.net.proxy.enable = true;
  features.net.lan-proxy.enable = true;

  features.dev.haskell.enable = false; # Disable Haskell toolchain (saves ~1GB)
  features.dev.cpp.enable = true; # Enable C++ toolchain (ccache, gcc, cmake)

  boot.plymouth = {
    enable = true;
    theme = "lone";
    themePackages = [
      (pkgs.adi1090x-plymouth-themes.override {
        # collection of plymouth themes
        selected_themes = [
          "lone"
          "green_blocks"
        ];
      })
    ];
  };
}
