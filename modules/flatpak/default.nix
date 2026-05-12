{ config, lib, ... }:
{
  imports = [ ./pkgs.nix ]; # Nix package manager
  services.flatpak = {
    enable = true;
    overrides = {
      global = {
        Environment = {
          XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons"; # Fix un-themed cursor in some Wayland apps
          GTK_THEME = "Adwaita:dark"; # Force correct theme for some GTK apps
        };
      };
      # "org.telegram.desktop" = {
      #   Environment = {
      #     GTK_USE_PORTAL = "1";
      #     QT_QPA_PLATFORMTHEME = "xdgdesktopportal";
      #     QT_QPA_PLATFORM = "wayland";
      #     XDG_SESSION_TYPE = "wayland";
      #   };
      # };
    };

    packages = [
      {
        appId = "com.obsproject.Studio";
        origin = "flathub";
      }
      {
        appId = "net.sapples.LiveCaptions";
        origin = "flathub";
      }
      {
        appId = "md.obsidian.Obsidian";
        origin = "flathub";
      }
      {
        appId = "org.chromium.Chromium";
        origin = "flathub";
      }
      {
        appId = "org.gimp.GIMP";
        origin = "flathub";
      }
      {
        appId = "com.google.Chrome";
        origin = "flathub";
      }
      # {
      #   appId = "org.telegram.desktop";
      #   origin = "flathub";
      # }
    ]
    ++ lib.optionals (config.features.apps.libreoffice.enable) [
      {
        appId = "org.libreoffice.LibreOffice";
        origin = "flathub";
      }
    ]
    ++ lib.optionals (config.features.games.launchers.lutris.enable) [
      {
        appId = "net.lutris.Lutris";
        origin = "flathub";
      }
    ];
    update.onActivation = true;
  };

  systemd.services.flatpak-managed-install.environment = {
    NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
    SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
    CURL_CA_BUNDLE = "/etc/ssl/certs/ca-bundle.crt";
    GIT_SSL_CAINFO = "/etc/ssl/certs/ca-bundle.crt";
  };
}
