{pkgs, ...}: {
  imports = [
    ../../profiles/desktop.nix
    ./hardware.nix
    ./networking.nix
    ./services.nix
    ./virtualisation/macos.nix
    ./virtualisation/lxc.nix
  ];

  boot.plymouth = {
    enable = true;
    theme = "lone";
    themePackages = with pkgs; [
      (adi1090x-plymouth-themes.override {
        selected_themes = ["lone"];
      })
    ];
  };
}
