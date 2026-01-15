{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.gui;
in
lib.mkIf (cfg.enable or false) {
  # User systemd services

  systemd.user.services = {
    # Pic dirs notifier
    "pic-dirs" = {
      description = "Pic dirs notification";
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

    # OpenRGB daemon
    openrgb = {
      description = "OpenRGB daemon with profile";
      partOf = [ "graphical-session.target" ];
      serviceConfig = {
        ExecStart =
          let
            exe = lib.getExe pkgs.openrgb; # Open source RGB lighting control
            args = [
              "--server"
              "-p"
              "neg.orp"
            ];
          in
          "${exe} ${lib.escapeShellArgs args}";
        RestartSec = "30";
      };
      wantedBy = [ "graphical-session.target" ];
    };

    # Local AI (Ollama)
    "local-ai" = {
      description = "Local AI (Ollama)";
      serviceConfig = {
        ExecStart = "${lib.getExe pkgs.ollama} serve"; # Get up and running with large language models locally
        Environment = [
          # For LocalAI compatibility
          "MODELS_PATH=${config.users.users.neg.home}/.local/share/localai/models"
          # Effective for Ollama
          "OLLAMA_MODELS=${config.users.users.neg.home}/.local/share/ollama"
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
