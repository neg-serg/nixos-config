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

  features.gui.walker.enable = false;
  features.hardware.amdgpu.rocm.enable = true;
  features.mail.enable = true;
  features.dev.hack.pentest = false;
  features.dev.cpp.enable = false; # Disable C++ toolchain (saves ~2GB)
  features.dev.haskell.enable = false; # Disable Haskell toolchain (saves ~1GB)
  features.fun.enable = false; # Disable Nix Steam (using Flatpak instead, saves ~5.5GB)
  services.speechd.enable = false;

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
