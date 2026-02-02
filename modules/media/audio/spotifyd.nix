{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.features.media.audio.spotify;
  spotifydPkg = pkgs.spotifyd;
  spotifydConf = pkgs.writeText "spotifyd.conf" ''
    [global]
    autoplay = true
    backend = pulseaudio
    bitrate = 320
    cache_path = ${config.users.users.neg.home}/.cache/spotifyd
    device_type = computer
    initial_volume = 100
    password_cmd = cat ${config.sops.secrets."spotify-password".path}
    username_cmd = cat ${config.sops.secrets."spotify-username".path}
    use_mpris = true
    volume_normalisation = false
  '';
in
{
  config = lib.mkIf (cfg.enable or false) {
    # Sops secrets for Spotify credentials
    sops.secrets."spotify-username" = {
      sopsFile = ../../../secrets/home/spotify.sops.yaml;
      owner = "neg";
      key = "username";
    };
    sops.secrets."spotify-password" = {
      sopsFile = ../../../secrets/home/spotify.sops.yaml;
      owner = "neg";
      key = "password";
    };

    # Spotifyd systemd user service
    systemd.user.services.spotifyd = {
      description = "Spotify daemon";
      wantedBy = [ "graphical-session.target" ];
      after = [
        "graphical-session.target"
        "pipewire.service"
      ];
      serviceConfig = {
        ExecStart = "${spotifydPkg}/bin/spotifyd --no-daemon --config-path ${spotifydConf}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    # TUI client for controlling spotifyd
    environment.systemPackages = [
      spotifydPkg
      pkgs.spotify-tui # TUI Spotify client
    ];
  };
}
