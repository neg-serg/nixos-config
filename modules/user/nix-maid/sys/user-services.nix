{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.gui;
  alertmanagerWebhook = pkgs.writeShellApplication {
    name = "alertmanager-webhook";
    runtimeInputs = [
      pkgs.curl # HTTP data transfer utility
      pkgs.python3 # Python interpreter
    ];
    text = ''
          # mpdas — Last.fm AudioScrobbler (ported from legacy Salt config)
          # Routes via SOCKS5 proxy if available (127.0.0.1:10808)
          mpdas = lib.mkIf (config.features.media.audio.mpd.enable or false) {
            description = "MPD AudioScrobbler (Last.fm)";
            after = [ "mpd.service" "network-online.target" ];
            serviceConfig = {
              ExecStart = "${lib.getExe pkgs.mpdas}";
              Environment = [
                "ALL_PROXY=socks5h://127.0.0.1:10808"
                "MPD_HOST=127.0.0.1"
                "MPD_PORT=6600"
              ];
              Restart = "on-failure";
              RestartSec = 10;
            };
            wantedBy = [ "default.target" ];
          };

          # Alertmanager Telegram webhook bridge
            # Receives alerts from Alertmanager at 127.0.0.1:9094/alert,
            # formats and forwards to Telegram
            TELEGRAM_BOT_TOKEN="''${TELEGRAM_BOT_TOKEN:-}"
            TELEGRAM_CHAT_ID="''${TELEGRAM_CHAT_ID:-}"

            if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
              echo "Error: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID must be set"
              exit 1
            fi

            exec python3 -c '
      import os, json, sys
      from http.server import HTTPServer, BaseHTTPRequestHandler
      from urllib.request import urlopen, Request

      TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
      CHAT_ID = os.environ.get("TELEGRAM_CHAT_ID", "")

      class Handler(BaseHTTPRequestHandler):
          def do_POST(self):
              length = int(self.headers.get("Content-Length", 0))
              body = self.rfile.read(length)
              data = json.loads(body)
              for alert in data.get("alerts", []):
                  status = alert.get("status", "UNKNOWN").upper()
                  labels = alert.get("labels", {})
                  annotations = alert.get("annotations", {})
                  name = labels.get("alertname", "Unknown")
                  severity = labels.get("severity", "unknown")
                  summary = annotations.get("summary", "No summary")
                  msg = f"[{status}] [{severity}] {name}: {summary}"
                  if TOKEN and CHAT_ID:
                      req = Request(
                          f"https://api.telegram.org/bot{TOKEN}/sendMessage",
                          data=f"chat_id={CHAT_ID}&text={msg}".encode(),
                          headers={"Content-Type": "application/x-www-form-urlencoded"}
                      )
                      urlopen(req)
              self.send_response(200)
              self.end_headers()
              self.wfile.write(b"OK")

          def log_message(self, format, *args):
              pass

      HTTPServer(("127.0.0.1", 9094), Handler).serve_forever()
      '
    '';
  };
in
lib.mkIf (cfg.enable or false) {
  # User systemd services

  systemd.user.services = {
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

    # Alertmanager Telegram webhook bridge
    # Forwards alerts from Alertmanager (127.0.0.1:9093) to Telegram.
    # Requires TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID environment variables
    # (set via SOPS secret or environment). Ported from legacy Salt config.
    alertmanager-webhook = lib.mkIf (config.monitoring.logs.enable or false) {
      description = "Alertmanager Telegram webhook bridge";
      documentation = [ "https://prometheus.io/docs/alerting/latest/configuration/#webhook_config" ];
      after = [ "network-online.target" ];
      partOf = [ "alertmanager.service" ];
      serviceConfig = {
        ExecStart = "${lib.getExe alertmanagerWebhook}";
        Restart = "on-failure";
        RestartSec = 5;
      };
      wantedBy = [ "default.target" ];
    };
  };
}
