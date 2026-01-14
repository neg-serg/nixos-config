{ ... }:
{
  imports = [ ./pkgs.nix ];
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
        appId = "org.zealdocs.Zeal";
        origin = "flathub";
      }
      {
        appId = "org.chromium.Chromium";
        origin = "flathub";
      }
      {
        appId = "org.libreoffice.LibreOffice";
        origin = "flathub";
      }
    ];
    update.onActivation = false;
  };
}
