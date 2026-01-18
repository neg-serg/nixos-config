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
    update.onActivation = false;
  };
}
