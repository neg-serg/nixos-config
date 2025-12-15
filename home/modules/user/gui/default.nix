{
  imports = [
    ./wezterm.nix
    ./apps.nix
    ./flameshot.nix
    ./hyprland.nix
    ./kitty.nix
    ./vicinae.nix
    ./handlr.nix
    ./rofi.nix
    ./wayland.nix
    ./discord.nix
    ./quickshell.nix
    ./walker.nix
    ./swayosd
    ./qt.nix
    ./spicetify/default.nix
    ./nekoray/default.nix
    # ./plasma-manager/default.nix
  ];

  systemd.user.targets.graphical-session = {
    Unit = {
      RefuseManualStart = false;
    };
  };
}
