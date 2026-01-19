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

  # Wrapped rofi with custom config in XDG_DATA_DIRS
  rofiWrapped =
    pkgs.runCommand "rofi-wrapped"
      {
        nativeBuildInputs = [ pkgs.makeWrapper ];
      }
      ''
        mkdir -p $out/bin
        makeWrapper ${rofiWithPlugins}/bin/rofi $out/bin/rofi \
          --prefix PATH : ${
            lib.makeBinPath [
              pkgs.gawk # awk for text processing
              pkgs.gnused # sed for stream editing
              pkgs.jq # JSON processor
            ]
          } \
          --prefix XDG_DATA_DIRS : ${pkgs.neg.rofi-config}/share

        # Copy other files from rofiWithPlugins
        for dir in ${rofiWithPlugins}/*; do
          if [ "$(basename "$dir")" != "bin" ]; then
            ln -s "$dir" "$out/$(basename "$dir")"
          fi
        done
      '';
in
{
  config = lib.mkMerge [
    {
      # Override rofi package to use wrapped version with custom config
      neg.rofi.package = rofiWrapped;

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
        pkgs.neg.rofi-config # Custom scripts (launcher, powermenu)
        pkgs.swayosd # OSD for volume/brightness on Wayland
        pkgs.wallust # Color palette generator
        pkgs.wlogout # Logout menu
      ];
    }
    (n.mkHomeFiles {
      # Rofi configuration directory (symlink to nix store)
      ".config/rofi".source = "${pkgs.neg.rofi-config}/share/rofi";

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
