{
  pkgs,
  lib,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;

  # Rofi with plugins (file-browser-extended)
  rofiWithPlugins = pkgs.rofi.override {
    # Window switcher, run dialog and dmenu replacement
    plugins = [
      pkgs.rofi-file-browser # adds file browsing capability to rofi
      pkgs.rofi-emoji # adds emoji selection to rofi
      pkgs.rofi-calc # adds calculator capability to rofi
    ];
  };
in
{
  config = lib.mkMerge [
    {
      # Rofi Wrapper using wrapper-manager
      wrappers.rofi = {
        basePackage = rofiWithPlugins;
        pathAdd = [
          pkgs.gawk # awk for text processing
          pkgs.gnused # sed for stream editing
          pkgs.jq # JSON processor
        ];
        env.XDG_DATA_DIRS.append = "${pkgs.neg.rofi-config}/share";
      };

      # Systemd user services
      systemd.user.services = {
        # SwayOSD LibInput Backend
        swayosd-libinput-backend = {
          description = "SwayOSD LibInput Backend";
          after = [ "graphical-session.target" ];
          wantedBy = [ "graphical-session.target" ];
          serviceConfig = {
            ExecStart = "${lib.getExe' pkgs.swayosd "swayosd-libinput-backend"}"; # GTK based on screen display for keyboard shortcuts
            Restart = "always";
          };
        };
      };

      # Packages
      environment.systemPackages = [
        # rofiWithPlugins is wrapped by wrappers.rofi
        pkgs.neg.rofi-config # Custom scripts (launcher, powermenu)
        pkgs.swayosd # OSD for volume/brightness on Wayland
        pkgs.wallust # Color palette generator
        pkgs.wlogout # Logout menu
      ];
    }
    (n.mkHomeFiles {
      # Handlr Config
      ".config/handlr/handlr.toml".text = ''
        enable_selector = false
        selector = "rofi -dmenu -p 'Open With: ❯>'"
      '';

      # wlogout config
      ".config/wlogout".source = ../../../../files/config/wlogout;
    })
  ];
}
