{
  pkgs,
  lib,
  config,
  ...
}: let
  cfg = config.features.gui;
in
  lib.mkIf (cfg.enable or false) {
    # Migrated services from home/modules/user/systemd/default.nix

    systemd.user.services = {
      # Pic dirs notifier
      "pic-dirs" = {
        description = "Pic dirs notification";
        serviceConfig = {
          ExecStart = let
            runner = pkgs.writeShellApplication {
              name = "pic-dirs-runner";
              text = ''
                set -euo pipefail
                # Assuming pic-dirs-list is in PATH (e.g. from local-bin)
                exec pic-dirs-list
              '';
            };
          in "${lib.getExe runner}";
          PassEnvironment = ["XDG_PICTURES_DIR" "XDG_DATA_HOME"];
          Restart = "on-failure";
          RestartSec = "1";
        };
        wantedBy = ["default.target"];
      };

      # OpenRGB daemon
      openrgb = {
        description = "OpenRGB daemon with profile";
        partOf = ["graphical-session.target"];
        serviceConfig = {
          ExecStart = let
            exe = lib.getExe pkgs.openrgb;
            args = ["--server" "-p" "neg.orp"];
          in "${exe} ${lib.escapeShellArgs args}";
          RestartSec = "30";
        };
        wantedBy = ["graphical-session.target"];
      };

      # Local AI (Ollama)
      "local-ai" = {
        description = "Local AI (Ollama)";
        serviceConfig = {
          ExecStart = "${pkgs.ollama}/bin/ollama serve";
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
        wantedBy = ["default.target"];
      };

      # Udiskie (Automounter)
      udiskie = {
        description = "Udiskie automounter";
        serviceConfig = {
          ExecStart = "${lib.getExe pkgs.udiskie} --no-tray";
          # Environment from HM override (Wayland specific)
          Environment = ["QT_QPA_PLATFORM=wayland" "XDG_SESSION_TYPE=wayland"];
          Restart = "on-failure";
          RestartSec = "2";
        };
        wantedBy = ["graphical-session.target"];
      };
    };
  }
