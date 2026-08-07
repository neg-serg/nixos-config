{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (config.users.users.neg) home;
  cfg = config.features.gui;
in
lib.mkIf (cfg.enable or false) {
  # User systemd services

  systemd.user.services = {
    # mpdas — Last.fm AudioScrobbler for MPD. Credentials from sops secret.
    mpdas =
      lib.mkIf
        (
          (config.features.media.audio.mpd.enable or false)
          && builtins.pathExists ../../../../secrets/home/mpdas/neg.rc
        )
        {
          description = "MPD AudioScrobbler (Last.fm)";
          after = [
            "network-online.target"
            "mpd.service"
          ];
          wants = [ "mpd.service" ];
          serviceConfig = {
            ExecStart = "${lib.getExe pkgs.mpdas} -c ${config.sops.secrets.mpdas_negrc.path}";
            Environment = [
              "MPD_HOST=127.0.0.1"
              "MPD_PORT=6600"
            ];
            Restart = "on-failure";
            RestartSec = 10;
          };
          wantedBy = [ "default.target" ];
        };

    # Pic dirs notifier
    "pic-dirs" = {
      description = "Pic dirs notification";
      unitConfig = {
        ConditionUser = "!greeter";
      };
      path = [
        pkgs.inotify-tools # Filesystem event monitor
        pkgs.zoxide # Smarter cd command
      ];
      serviceConfig = {
        ExecStart = "%h/.local/bin/pic-dirs-list";
        PassEnvironment = [
          "XDG_PICTURES_DIR"
          "XDG_DATA_HOME"
        ];
        Restart = "on-failure";
        RestartSec = "1";
      };
      wantedBy = [ "default.target" ];
    };

    # OpenRGB daemon — starts the SDK server so clients (profile service, GUI) can connect.
    # The profile is NOT loaded on daemon startup (it may not exist yet); the
    # openrgb-profile oneshot applies the saved "neg" profile after the server is ready.
    openrgb = {
      description = "OpenRGB SDK server";
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.openrgb} --server"; # SDK server for RGB control
        Restart = "on-failure";
        RestartSec = "30";
      };
      wantedBy = [ "graphical-session.target" ];
    };

    # OpenRGB profile — applies saved "neg" profile after daemon starts.
    # If no profile has been saved yet (first run), this will produce a "Profile
    # failed to load" message but does NOT fail the unit — status=0 is expected.
    # Save a profile named "neg" via the GUI or CLI to make this effective.
    openrgb-profile = {
      description = "Apply OpenRGB neg profile";
      after = [ "openrgb.service" ];
      requires = [ "openrgb.service" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${lib.getExe pkgs.openrgb} -p %h/.config/openrgb/neg.orp";
        RemainAfterExit = false;
      };
      wantedBy = [ "graphical-session.target" ];
    };

    # Local AI (Ollama)
    "local-ai" = lib.mkIf (config.features.llm.enable or false) {
      description = "Local AI (Ollama)";
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.ollama} serve"; # Get up and running with large language models locally
        Environment = [
          # For LocalAI compatibility
          "MODELS_PATH=${home}/.local/share/localai/models"
          # Effective for Ollama
          "OLLAMA_MODELS=${home}/.local/share/ollama"
          "OLLAMA_HOST=127.0.0.1:11434"
        ];
        Restart = "on-failure";
        RestartSec = "2s";
      };
      wantedBy = [ "default.target" ];
    };

    # Udiskie (Automounter)
    udiskie = {
      description = "Udiskie automounter";
      serviceConfig = {
        ExecStart = "${lib.getExe' pkgs.udiskie "udiskie"} --no-tray"; # Removable disk automounter for udisks
        # Wayland-specific environment
        Environment = [
          "QT_QPA_PLATFORM=wayland"
          "XDG_SESSION_TYPE=wayland"
        ];
        Restart = "on-failure";
        RestartSec = "2";
      };
      wantedBy = [ "graphical-session.target" ];
    };

  };
}
