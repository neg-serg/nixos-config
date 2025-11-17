{
  lib,
  config,
  pkgs,
  systemdUser,
  ...
}: let
  featureEnabled = config.features.media.audio.mpd.enable or false;
  guiEnabled = config.features.gui.enable or false;
  mpdCfg = config.media.audio.mpd;
  cantataCfg = mpdCfg.cantata;
  cantataPkg = pkgs.neg.cantata or pkgs.cantata;
in {
  options.media.audio.mpd.cantata = {
    autostart =
      (lib.mkEnableOption "autostart Cantata after the graphical session is ready (systemd user service)")
      // {default = false;};
  };

  config = lib.mkIf featureEnabled (
    lib.mkMerge [
      {
        home.packages = config.lib.neg.pkgsList [
          cantataPkg
        ];
      }

      (lib.mkIf (cantataCfg.autostart && guiEnabled) (
        systemdUser.mkSimpleService {
          name = "cantata";
          description = "Cantata MPD client";
          execStart = lib.getExe cantataPkg;
          presets = ["graphical"];
          serviceExtra = {
            Environment = [
              "MPD_HOST=${mpdCfg.host}"
              "MPD_PORT=${toString mpdCfg.port}"
            ];
            Restart = "on-failure";
            RestartSec = 5;
          };
        }
      ))
    ]
  );
}
