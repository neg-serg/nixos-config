{ pkgs, ... }:
{
  imports = [

    ./hardware.nix
    ./networking.nix
    ./services.nix
    # ./virtualisation/macos.nix  # Archived - MacOS VM not currently in use
    ./virtualisation/lxc.nix
  ];

  system.preserveFlake = true;

  features.gui.walker.enable = false;
  features.hardware.amdgpu.rocm.enable = true;
  features.mail.enable = true;
  features.dev.hack.pentest = false;
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
