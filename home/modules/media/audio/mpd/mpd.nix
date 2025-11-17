{
  config,
  lib,
  pkgs,
  systemdUser,
  ...
}: let
  inherit (lib) mkOption types;
  cfg = config.media.audio.mpd;
  featureEnabled = config.features.media.audio.mpd.enable;
in {
  options.media.audio.mpd = {
    host = mkOption {
      type = types.str;
      default = "localhost";
      description = "MPD host used by clients (also exported via MPD_HOST).";
      example = "127.0.0.1";
    };

    port = mkOption {
      type = types.port;
      default = 6600;
      description = "MPD port used by clients (also exported via MPD_PORT).";
    };
  };

  config = lib.mkIf featureEnabled (lib.mkMerge [
    {
      home.packages = config.lib.neg.pkgsList [
        pkgs.rmpc # alternative tui client with album cover
      ];

      home.sessionVariables = {
        MPD_HOST = cfg.host;
        MPD_PORT = toString cfg.port;
      };

      services.mpd = {
        enable = false;
        dataDir = "${config.xdg.stateHome}/mpd";
        musicDirectory = "${config.home.homeDirectory}/music";
      };

      services.mpdris2 = {
        enable = true;
        mpd.host = cfg.host;
        mpd.port = cfg.port;
      };

      systemd.user.services = {
        mpdas = lib.mkMerge [
          {
            Unit = {Description = "mpdas last.fm scrobbler";};
            Service = {
              ExecStart = let
                exe = lib.getExe pkgs.mpdas;
                args = ["-c" config.sops.secrets.mpdas_negrc.path];
              in "${exe} ${lib.escapeShellArgs args}";
              Restart = "on-failure";
              RestartSec = "2";
            };
          }
          (systemdUser.mkUnitFromPresets {
            # wait for sops-nix to provision the secret; defaultWanted for login start
            presets = ["sops" "defaultWanted"];
            after = ["sound.target"]; # preserve additional ordering
          })
        ];
      };
    }
    # Soft migration notice removed (default points to XDG state; no warning needed)
  ]);
}
