{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  exoEnabled =
    config.features.gui.enable or false
    && config.features.gui.exo.enable or false
    && !(config.features.devSpeed.enable or false);

  exoPkg = pkgs.exo;

  # Ignis runtime dependencies (need to be in PATH for ignis init)
  ignisRuntimeDeps = [
    pkgs.matugen # Material You color generator for wallpaper-based theming
    pkgs.dart-sass # SASS/SCSS compiler for ignis CSS styles
    pkgs.awww # animated wallpaper daemon for Wayland
    pkgs.gnome-bluetooth # Bluetooth support for quick settings
    pkgs.material-symbols # Material Symbols icon font
  ];

  # Ignis wrapper with runtime deps in PATH
  ignisWrapped = pkgs.symlinkJoin {
    name = "ignis-wrapped";
    paths = [
      (pkgs.runCommand "ignis-wrapper"
        {
          nativeBuildInputs = [ pkgs.makeWrapper ];
        }
        ''
          mkdir -p $out/bin
          makeWrapper ${lib.getExe pkgs.ignis} $out/bin/ignis \
            --prefix PATH : ${lib.makeBinPath ignisRuntimeDeps} \
            --prefix GI_TYPELIB_PATH : ${
              lib.makeSearchPath "lib/girepository-1.0" [
                pkgs.gtk4 # GTK4 toolkit
                pkgs.libadwaita # GTK4 Libadwaita widget library
                pkgs.gobject-introspection # GObject introspection bindings
                pkgs.glib # GLib core library
                pkgs.pango # Pango text layout library
                pkgs.gdk-pixbuf # GDK Pixbuf image loader
                pkgs.graphene # Graphics primitive types library
              ]
            }
        ''
      )
    ];
  };

  # Ignis config source path in exo package
  ignisConfigSrc = "${exoPkg}/share/exo/ignis";
  matugenConfigSrc = "${exoPkg}/share/exo/matugen";
  exoDefaultsSrc = "${exoPkg}/share/exo/exodefaults";

  # Read top-level entries in ignis config dir for symlinking
  ignisSrcEntries = builtins.readDir ignisConfigSrc;

  # Files to exclude from symlinks (user-writable: generated at runtime)
  protectedIgnisFiles = [
    "user_settings.json"
    "colors.scss"
  ];

  ignisSrcNames = builtins.filter (name: !(builtins.elem name protectedIgnisFiles)) (
    builtins.attrNames ignisSrcEntries
  );

  ignisHomeFiles = builtins.listToAttrs (
    map (name: {
      name = ".config/ignis/${name}";
      value = {
        source = "${ignisConfigSrc}/${name}";
      };
    }) ignisSrcNames
  );

  matugenHomeFiles = {
    ".config/matugen".source = matugenConfigSrc;
  };

  # Oneshot: initialize user_settings.json if missing
  exoInitScript = pkgs.writeShellScript "exo-init" ''
    set -euo pipefail

    # Create user_settings.json if it doesn't exist
    settings_file="$HOME/.config/ignis/user_settings.json"
    if [ ! -f "$settings_file" ]; then
      echo '{}' > "$settings_file"
    fi

    # Copy preview-colors.scss if it doesn't exist (needed for wallpaper previews)
    preview_colors="$HOME/.config/ignis/styles/preview-colors.scss"
    if [ ! -f "$preview_colors" ]; then
      cp "${exoDefaultsSrc}/preview-colors.scss" "$preview_colors"
      chmod u+w "$preview_colors"
    fi

    # Ensure default wallpaper exists
    wallpaper_dir="$HOME/Pictures/Wallpapers"
    default_wallpaper="$wallpaper_dir/default.png"
    if [ ! -f "$default_wallpaper" ]; then
      mkdir -p "$wallpaper_dir"
      cp "${exoDefaultsSrc}/default_wallpaper.png" "$default_wallpaper"
    fi

    # Generate initial colors with matugen if colors.scss doesn't exist
    colors_file="$HOME/.config/ignis/colors.scss"
    if [ ! -f "$colors_file" ] && [ -f "$default_wallpaper" ]; then
      matugen image "$default_wallpaper" || true
    fi
  '';
in
lib.mkIf exoEnabled (
  lib.mkMerge [
    {
      environment.systemPackages = [
        ignisWrapped # Ignis shell framework with runtime deps (for Exo)
        pkgs.awww # animated wallpaper daemon for Wayland
        pkgs.dart-sass # SASS/SCSS compiler for ignis CSS styles
        pkgs.matugen # Material You color generator
        pkgs.adw-gtk3 # GTK3 theme for Adwaita-based apps
      ];

      # Ignis/Exo shell service
      systemd.user.services.ignis = {
        enable = true;
        description = "Ignis - Exo desktop shell (Material 3)";
        documentation = [ "https://github.com/debuggyo/Exo" ];
        partOf = [ "graphical-session.target" ];
        after = [
          "graphical-session-pre.target"
          "pipewire.service"
        ];
        wants = [ "pipewire.service" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${lib.getExe ignisWrapped} init";
          Restart = "on-failure";
          RestartSec = 2;
        };
      };

      # awww-daemon service (required for wallpaper animations)
      systemd.user.services.awww-daemon = {
        enable = true;
        description = "awww wallpaper daemon";
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session-pre.target" ];
        before = [ "ignis.service" ];
        wantedBy = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.awww}-daemon";
          Restart = "on-failure";
          RestartSec = 1;
        };
      };
    }

    (neg.mkHomeFiles (ignisHomeFiles // matugenHomeFiles))

    {
      # Remove old whole-directory symlinks before nix-maid deploys individual entries
      systemd.user.services.exo-cleanup-symlink = {
        description = "Remove old ignis/matugen symlinks before nix-maid activation";
        before = [ "maid-activation.service" ];
        wantedBy = [ "maid-activation.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "exo-cleanup-symlink" ''
            for dir in "$HOME/.config/ignis" "$HOME/.config/matugen"; do
              if [ -L "$dir" ]; then
                rm "$dir"
              fi
            done
          '';
        };
      };

      systemd.user.services.exo-init = {
        description = "Initialize Exo user files before ignis starts";
        after = [ "maid-activation.service" ];
        before = [ "ignis.service" ];
        requiredBy = [ "ignis.service" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${exoInitScript}";
        };
      };

      systemd.user.services.ignis.after = lib.mkForce [
        "graphical-session-pre.target"
        "maid-activation.service"
        "pipewire.service"
        "awww-daemon.service"
        "exo-init.service"
      ];
      systemd.user.services.ignis.wants = [
        "maid-activation.service"
        "exo-init.service"
      ];
    }
  ]
)
