{ ... }: {
  imports = [ ./pkgs.nix ];
  services.flatpak = {
    enable = true;
    overrides = {
      global = {
        Environment = {
          XCURSOR_PATH = "/run/host/user-share/icons:/run/host/share/icons"; # Fix un-themed cursor in Wayland apps
        };
      };
    };

    packages = [
      {
        appId = "md.obsidian.Obsidian";
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
