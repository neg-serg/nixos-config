{
  lib,
  config,
  pkgs,
  ...
}: let
  cfg = config.features.media.audio.spotify;
in {
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

    # Spotifyd system service (runs as user)
    services.spotifyd = {
      enable = true;
      package = pkgs.spotifyd.override {withMpris = true;};
      settings.global = {
        autoplay = true;
        backend = "pulseaudio";
        bitrate = 320; # Maximum quality (requires Premium)
        cache_path = "/home/neg/.cache/spotifyd";
        device_type = "computer";
        initial_volume = "100";
        # Credentials from sops secrets
        password_cmd = "cat ${config.sops.secrets."spotify-password".path}";
        username_cmd = "cat ${config.sops.secrets."spotify-username".path}";
        use_mpris = true; # MPRIS integration for media controls
        volume_normalisation = false;
      };
    };

    # TUI client for controlling spotifyd
    environment.systemPackages = [
      pkgs.spotify-tui # TUI Spotify client
    ];
  };
}
