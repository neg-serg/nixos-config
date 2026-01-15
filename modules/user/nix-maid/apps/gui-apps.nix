{
  pkgs,
  lib,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  # Rofi config source path
  rofiConfigSrc = ../../../../packages/rofi-config;

  # Rofi with plugins (file-browser-extended)
  rofiWithPlugins = pkgs.rofi.override { # Window switcher, run dialog and dmenu replacement
    # Window switcher, run dialog and dmenu replacement
    plugins = [
      pkgs.rofi-file-browser # adds file browsing capability to rofi
      pkgs.rofi-emoji # adds emoji selection to rofi
      pkgs.rofi-calc # adds calculator capability to rofi
    ];
  };

  # Rofi wrapper script
  rofiWrapperScript = builtins.readFile ../../../../files/rofi/rofi-wrapper.sh;
  rofiWrapper = pkgs.writeShellApplication {
    name = "rofi-wrapper";
    runtimeInputs = [
      pkgs.gawk # awk for simple text processing
      pkgs.gnused # sed for stream editing
      pkgs.jq # JSON processor
      rofiWithPlugins # Rofi launcher with plugins
    ];
    text =
      builtins.replaceStrings
        [ "@ROFI_BIN@" "@JQ_BIN@" ]
        [ "${rofiWithPlugins}/bin/rofi" "${pkgs.jq}/bin/jq" ] # Lightweight and flexible command-line JSON processor
        rofiWrapperScript;
  };

  # Rofi local bin wrapper
  rofiLocalBin = pkgs.writeShellScriptBin "rofi" ''
    #!/usr/bin/env bash
    set -euo pipefail
    exec ${rofiWrapper}/bin/rofi-wrapper "$@"
  '';
in
{
  config = lib.mkMerge [
    {
      # Packages
      neg.rofi.package = rofiWithPlugins;

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
        rofiWithPlugins # Rofi launcher with plugins (Wayland/X11)
        pkgs.swayosd # OSD for volume/brightness on Wayland
        rofiLocalBin # Rofi wrapper script (shadows standard rofi bin)
        pkgs.wallust # Color palette generator
        pkgs.wlogout # Logout menu
      ];
    }
    (n.mkHomeFiles {
      # Rofi config directory
      ".config/rofi".source = rofiConfigSrc;

      # Rofi themes in XDG data dir
      ".local/share/rofi/themes".source = rofiConfigSrc;

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
