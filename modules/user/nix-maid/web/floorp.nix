{
  config,
  lib,
  pkgs,
  negLib,
  neg,
  impurity ? null,
  ...
}:
let
  cfg = config.features.web.floorp;
  guiEnabled = config.features.gui.enable or false;

  commonConfig = config // {
    home.homeDirectory = config.users.users.neg.home;
  };
  mozillaCommon = import ./mozilla-common-lib.nix {
    inherit lib pkgs negLib;
    config = commonConfig;
  };
  inherit (mozillaCommon) mkMozillaModule;

  # Floorp settings
  profileId = "bqtlgdxw.default";

  profiles = {
    default = {
      id = 0;
      name = "default";
      path = profileId;
      settings = {
        "widget.use-xdg-desktop-portal.file-picker" = 1;

        # Proxy settings - disable proxy (reset from Hiddify)
        "network.proxy.type" = 0;
        "network.proxy.http" = "";
        "network.proxy.http_port" = 0;
        "network.proxy.ssl" = "";
        "network.proxy.ssl_port" = 0;
        "network.proxy.socks" = "";
        "network.proxy.socks_port" = 0;
        "network.proxy.no_proxies_on" = "localhost, 127.0.0.1";

        "browser.download.useDownloadDir" = true;
        "browser.helperApps.neverAsk.saveToDisk" =
          "image/jpeg,image/png,image/gif,image/webp,image/svg+xml,image/avif,image/bmp,video/mp4,video/webm,video/ogg,video/x-matroska,video/avi,audio/mpeg,audio/wav,audio/ogg,audio/flac,audio/aac,audio/webm";
      };
      userChrome = mozillaCommon.userChrome;
      userContent = mozillaCommon.surfingkeysUserContent;
      enable = true;
      isDefault = true;
      extensions = [ ];
    };
  };
in
{
  config = lib.mkIf (guiEnabled && (cfg.enable or false)) (
    lib.mkMerge [
      (mkMozillaModule {
        inherit
          impurity
          neg
          cfg
          guiEnabled
          profiles
          ;
        package = pkgs.floorp-bin; # Fork of Firefox that seeks balance between versatility, p...
        browserType = "floorp";
      }).config
      {
        environment.sessionVariables = {
          MOZ_DBUS_REMOTE = "1";
          MOZ_ENABLE_WAYLAND = "1";
        };

        # Additional Floorp-specific home files
      }
    ]
  );
}
