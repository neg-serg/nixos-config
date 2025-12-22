{pkgs, ...}: {
  imports = [
    ../../profiles/desktop.nix
    ./hardware.nix
    ./networking.nix
    ./services.nix
    ./virtualisation/macos.nix
    ./virtualisation/lxc.nix
  ];

  system.preserveFlake = true;

  features.hardware.amdgpu.rocm.enable = true;
  features.mail.enable = true;

  boot.plymouth = {
    enable = true;
    theme = "lone";
    themePackages = [
      (pkgs.adi1090x-plymouth-themes.override {
        selected_themes = ["lone" "green_blocks"];
      })
    ];
  };
}
