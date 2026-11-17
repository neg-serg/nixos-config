{ neg, ... }: {
  imports = neg.importDir {
    dir = ./.;
    includeDirs = true;
  };
  services.flatpak = {
    enable = true;
    overrides = {
      global = {
        Environment = {
          XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons"; # Fix un-themed cursor in Wayland apps
        };
      };

      # PortProton's upstream scripts deliberately write into $HOME: start.sh
      # runs `ln -s "$PORT_WINE_PATH" "$HOME/PortProton"`, and setup.sh copies
      # its .desktop into `$(xdg-user-dir DESKTOP)`. The manifest grants
      # `filesystems=host`, so $HOME is the real home and both land there as
      # litter. Dropping host access confines those writes to the sandbox's
      # synthetic home; the game locations stay reachable. PortProton's own
      # state (~1-2 GiB) lives in ~/.var/app/ru.linux_gaming.PortProton/data
      # regardless: flatpak pins XDG_DATA_HOME and ignores --env overrides.
      "ru.linux_gaming.PortProton" = {
        Context.filesystems = [
          "!host"
          "~/games" # extracted Windows games, launched in place
          "/gamez" # Steam library and game installs
          "~/dw:ro" # downloaded installers and images
          "~/torrent:ro" # torrent drops (ISO/images)
          "~/.local/share/Steam:ro" # native Steam install, for its library
        ];
      };
    };

    packages = [
      {
        appId = "md.obsidian.Obsidian";
        origin = "flathub";
      }
      {
        # Windows-game launcher for non-Steam titles (per-game prefixes,
        # bundled Proton/GE builds). Game data stays on /gamez; Steam's own
        # Proton and features.wine.apps are untouched.
        appId = "ru.linux_gaming.PortProton";
        origin = "flathub";
      }
    ];
    update.onActivation = false;
  };

  systemd.services.flatpak-managed-install.environment = {
    NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
    SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
    CURL_CA_BUNDLE = "/etc/ssl/certs/ca-bundle.crt";
    GIT_SSL_CAINFO = "/etc/ssl/certs/ca-bundle.crt";
  };
}
