{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
let
  unboundLocalData = import ./unbound-hosts.nix;
  resilioAuthScript = pkgs.writeShellScript "resilio-auth" ''
    CONFIG_FILE="/run/rslsync/config.json"

    if [ ! -f "$CONFIG_FILE" ]; then
      echo "Config file not found at $CONFIG_FILE"
      exit 1
    fi

    chmod 600 "$CONFIG_FILE"

    LOGIN=$(cat ${config.sops.secrets."resilio/http-login".path})
    PASS=$(cat ${config.sops.secrets."resilio/http-pass".path})

    ${lib.getExe' pkgs.gnused "sed"} -i "s|placeholder_login|$LOGIN|" "$CONFIG_FILE" # GNU sed, a batch stream editor
    ${lib.getExe' pkgs.gnused "sed"} -i "s|placeholder_pass|$PASS|" "$CONFIG_FILE" # GNU sed, a batch stream editor
  '';

  # Alertmanager Telegram webhook bridge: HTTPServer on 127.0.0.1:9094 that
  # forwards every Alertmanager webhook notification to a Telegram chat.
  # Restored as a system service from git history
  # (fe1a52307^:modules/user/nix-maid/sys/user-services.nix).
  telegramBridgeScript = pkgs.writeShellApplication {
    name = "telegram-alert-bridge";
    runtimeInputs = [ pkgs.python3 ]; # Python runtime for the webhook listener
    text = ''
            set -euo pipefail

            TELEGRAM_BOT_TOKEN="$(cat ${config.sops.secrets."telegram/bot-token".path})"
            TELEGRAM_CHAT_ID="$(cat ${config.sops.secrets."telegram/chat-id".path})"

            if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
              echo "Error: TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID must be set" >&2
              exit 1
            fi
            # Export after assignment so cat failures are not masked (SC2155).
            export TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID

            exec python3 -c '
      import json
      import os
      from http.server import BaseHTTPRequestHandler, HTTPServer
      from urllib.parse import urlencode
      from urllib.request import Request, urlopen

      TOKEN = os.environ["TELEGRAM_BOT_TOKEN"]
      CHAT_ID = os.environ["TELEGRAM_CHAT_ID"]
      API_URL = "https://api.telegram.org/bot{0}/sendMessage".format(TOKEN)


      class Handler(BaseHTTPRequestHandler):
          def do_POST(self):
              length = int(self.headers.get("Content-Length", 0))
              data = json.loads(self.rfile.read(length))
              for alert in data.get("alerts", []):
                  status = str(alert.get("status", "UNKNOWN")).upper()
                  labels = alert.get("labels", {})
                  annotations = alert.get("annotations", {})
                  name = labels.get("alertname", "Unknown")
                  severity = labels.get("severity", "unknown")
                  summary = annotations.get("summary", "No summary")
                  msg = "[{0}] [{1}] {2}: {3}".format(status, severity, name, summary)
                  body = urlencode({"chat_id": CHAT_ID, "text": msg}).encode("utf-8")
                  urlopen(
                      Request(
                          API_URL,
                          data=body,
                          headers={"Content-Type": "application/x-www-form-urlencoded"},
                      )
                  )
              self.send_response(200)
              self.end_headers()
              self.wfile.write(b"OK")

          def log_message(self, format, *args):
              pass


      HTTPServer(("127.0.0.1", 9094), Handler).serve_forever()
      '
    '';
  };

  # Telegram alert scanner: python script run by a systemd timer every minute.
  # Posts into Alertmanager (wire format: array of
  # {labels: {alertname, severity}, annotations: {summary}, startsAt}):
  #   1. newly failed systemd units (diff against a persisted snapshot);
  #   2. OOM kills from the kernel journal (forward-only journal cursor);
  #   3. sshd brute-force attempts (>3 per scan window -> one alert).
  telegramAlertScannerScript = pkgs.writeText "telegram-alert-scanner.py" ''
    import datetime as dt
    import json
    import pathlib
    import re
    import subprocess
    import sys
    import urllib.error
    import urllib.request

    STATE_DIR = pathlib.Path("/var/lib/telegram-alert-scanner")
    FAILED_UNITS_FILE = STATE_DIR / "failed-units.json"
    OOM_CURSOR_FILE = STATE_DIR / "oom-journal-cursor"
    ALERTMANAGER_URL = "http://127.0.0.1:9093/api/v2/alerts" # v1 API removed in alertmanager 0.27+

    OOM_RE = re.compile(r"Out of memory: Killed process (\d+) \((\S+)\)")
    SSHD_FAIL_RE = re.compile(r"(Failed password|Invalid user)")
    SSH_FAIL_THRESHOLD = 3
    SSH_IP_RE = re.compile(r"\bfrom (\S+) port \d+")


    def now_iso():
        return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


    def run_cmd(args):
        try:
            proc = subprocess.run(args, capture_output=True, text=True, check=False)
            return proc.stdout or ""
        except OSError as exc:
            print("scanner: cannot run {}: {}".format(" ".join(args), exc), file=sys.stderr)
            return ""


    def post(alerts):
        if not alerts:
            return
        payload = json.dumps(alerts).encode("utf-8")
        req = urllib.request.Request(
            ALERTMANAGER_URL,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                resp.read()
        except (urllib.error.URLError, urllib.error.HTTPError, OSError) as exc:
            # Alertmanager may be starting; never fail the whole scan over this.
            print("scanner: cannot deliver alerts: {}".format(exc), file=sys.stderr)


    def make_alert(alertname, severity, summary, **labels):
        return {
            "labels": dict({"alertname": alertname, "severity": severity}, **labels),
            "annotations": {"summary": summary},
            "startsAt": now_iso(),
        }


    def scan_failed_units():
        """Newly failed systemd units; the snapshot forgets recovered units."""
        out = run_cmd(
            [
                "/run/current-system/sw/bin/systemctl",
                "list-units",
                "--failed",
                "--no-legend",
                "--plain",
                "--no-pager",
            ]
        )
        failed = {line.split()[0] for line in out.splitlines() if line.split()}
        previous = set()
        if FAILED_UNITS_FILE.exists():
            try:
                previous = set(json.loads(FAILED_UNITS_FILE.read_text()))
            except (ValueError, OSError) as exc:
                print("scanner: bad failed-unit snapshot: {}".format(exc), file=sys.stderr)
        if failed != previous:
            try:
                FAILED_UNITS_FILE.write_text(json.dumps(sorted(failed)))
            except OSError as exc:
                print("scanner: cannot save failed-unit snapshot: {}".format(exc), file=sys.stderr)
        return [
            make_alert(
                "systemd-failed-unit", "error", "Systemd unit failed: {}".format(unit), unit=unit
            )
            for unit in sorted(failed - previous)
        ]


    def journal_cursor(cursor_file):
        if cursor_file.exists():
            return cursor_file.read_text().strip()
        return None


    def advance_journal_cursor(output, cursor_file):
        """Persist the trailing '-- cursor:' marker if journalctl printed one."""
        m = re.search(r"(?m)^-- cursor: (\S+)$", output)
        if m:
            try:
                cursor_file.write_text(m.group(1))
            except OSError as exc:
                print("scanner: cannot save journal cursor: {}".format(exc), file=sys.stderr)


    def seed_journal_cursor(cursor_file):
        if journal_cursor(cursor_file):
            return
        output = run_cmd(
            [
                "/run/current-system/sw/bin/journalctl",
                "-n",
                "0",
                "--show-cursor",
                "--no-pager",
                "-o",
                "short",
            ]
        )
        advance_journal_cursor(output, cursor_file)


    def scan_oom_kills():
        """One aggregate alert for every OOM kill seen since the last scan."""
        seed_journal_cursor(OOM_CURSOR_FILE)
        cursor = journal_cursor(OOM_CURSOR_FILE)
        if not cursor:
            return []
        output = run_cmd(
            [
                "/run/current-system/sw/bin/journalctl",
                "--after-cursor=" + cursor,
                "--show-cursor",
                "--no-pager",
                "-o",
                "short",
            ]
        )
        advance_journal_cursor(output, OOM_CURSOR_FILE)
        kills = []
        for line in output.splitlines():
            m = OOM_RE.search(line)
            if m:
                kills.append(m.group(2))
        if not kills:
            return []
        summary = "{} OOM kill(s): {}".format(len(kills), ", ".join(sorted(set(kills))[:10]))
        return [make_alert("oom-kill", "error", summary, count=str(len(kills)))]


    def scan_sshd_bruteforce():
        """One alert per window when more than the threshold of failed logins occurs."""
        out = run_cmd(
            [
                "/run/current-system/sw/bin/journalctl",
                "-u",
                "sshd.service",
                "--since=-60s",
                "--no-pager",
                "-o",
                "short",
            ]
        )
        count = 0
        ips = set()
        for line in out.splitlines():
            if SSHD_FAIL_RE.search(line):
                count += 1
                m = SSH_IP_RE.search(line)
                if m:
                    ips.add(m.group(1))
        if count <= SSH_FAIL_THRESHOLD:
            return []
        summary = "{} failed sshd logins in the last minute from {} IP(s)".format(
            count, len(ips)
        )
        return [
            make_alert(
                "ssh-brute-force",
                "warning",
                summary,
                count=str(count),
                sources=", ".join(sorted(ips))[:200],
            )
        ]


    if __name__ == "__main__":
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        alerts = []
        alerts += scan_failed_units()
        alerts += scan_oom_kills()
        alerts += scan_sshd_bruteforce()
        post(alerts)
  '';
in
lib.mkMerge [
  {

    # Reduce microphone background noise system-wide (PipeWire RNNoise filter)
    # Enabled via modules/hardware/audio/noise by default for this host
    # (If you prefer toggling via an option, we can expose one later.)

    # Host-specific system policy
    system.autoUpgrade.enable = false;
    nix = {
      gc.automatic = false;
      optimise.automatic = false;
      settings.auto-optimise-store = false;
    };

    # Service profiles toggles for this host
    servicesProfiles = {
      unbound.enable = true;
      adguardhome.enable = true;
      # Local sshd, key-only auth (hardened profile). The dsh web agent has a
      # dedicated key in ~/.ssh/agent/dsh-agent-key (authorized_keys entry
      # restricted to localhost) so its SSH tools/terminal can reach the host.
      # Allow TCP forwarding so the agent's ssh_tunnel can reach local
      # services (databases, UIs); destinations are restricted to loopback
      # only via PermitOpen below, so the hardened profile stays intact.
      openssh.enable = true;
      openssh.allowTcpForwarding = true;
      # Local DNS rewrites for LAN names
      adguardhome.rewrites = [
        {
          domain = "odin";
          answer = "10.0.2.140";
        }
        {
          domain = "odin.local";
          answer = "10.0.2.140";
        }
      ];
      # Enable curated AdGuardHome filter lists
      adguardhome.filterLists = [
        # Core/general
        {
          name = "AdGuard DNS filter";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt";
          enabled = true;
        }
        {
          name = "OISD full";
          url = "https://big.oisd.nl/";
          enabled = true;
        }
        {
          name = "AdAway";
          url = "https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt";
          enabled = false;
        }

        # Well-known hostlists (mostly covered by OISD, kept optional)
        {
          name = "Peter Lowe's Blocklist";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_3.txt";
          enabled = false;
        }
        {
          name = "Dan Pollock's Hosts";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_4.txt";
          enabled = false;
        }
        {
          name = "Steven Black's List";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_33.txt";
          enabled = false;
        }

        # Security-focused
        {
          name = "Dandelion Sprout Anti‑Malware";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_12.txt";
          enabled = true;
        }
        {
          name = "Phishing Army";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_18.txt";
          enabled = true;
        }
        {
          name = "URLHaus Malicious URL";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt";
          enabled = true;
        }
        {
          name = "Scam Blocklist (DurableNapkin)";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_10.txt";
          enabled = true;
        }

        # Niche/optional
        {
          name = "NoCoin (Cryptomining)";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_8.txt";
          enabled = false;
        }
        {
          name = "Smart‑TV Blocklist";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_7.txt";
          enabled = false;
        }
        {
          name = "Game Console Adblock";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_6.txt";
          enabled = false;
        }
        {
          name = "1Hosts Lite";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt";
          enabled = false;
        }
        {
          name = "1Hosts Xtra";
          url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_70.txt";
          enabled = false;
        }

        # Regional (RU) — Adblock syntax lists; optional at DNS level
        {
          name = "AdGuard Russian filter";
          url = "https://filters.adtidy.org/extension/ublock/filters/2.txt";
          enabled = true;
        }
        {
          name = "RU AdList + EasyList";
          url = "https://easylist-downloads.adblockplus.org/ruadlist+easylist.txt";
          enabled = true;
        }
      ];
      # Enable Avahi (mDNS) so iOS/macOS can resolve *.local and discover SMB shares
      avahi.enable = true;
      # Enable Samba profile on this host (guest-access share under /zero/sync/smb)
      samba.enable = false;
    };
    # Static host rewrites pushed into Unbound (served to AdGuard Home upstream)

    # Disable RNNoise virtual mic for this host by default
    hardware.audio.rnnoise.enable = false;

    # LAN audio access: MPD on all interfaces (port 6600), PipeWire Pulse
    # TCP server (4713) + RTP multicast sink (224.0.0.56:46000 via net1)
    features.media.audio.lanAccess.enable = true;

    # Local speech stack: Chatterbox TTS (:8000), Piper TTS (:8001), whisper.cpp STT (:8002).
    # Assets in /zero/ai/speech/engines; whisper.cpp GPU via Vulkan, chatterbox via ROCm.
    # Disabled on request (2026-08-28): local speech NN servers (STT/TTS) turned off.
    features.media.audio.speech.enable = false;

    # AI image processing: realesrgan-ncnn-vulkan (upscale, Vulkan) + ffmpeg-full.
    features.media.aiUpscale.enable = true;

    # Quiet fan profile: load nct6775 and autogenerate fancontrol config
    hardware.cooling = {
      enable = true;
      autoFancontrol = {
        enable = true;
        # Aggressive silence at idle, ramp up quickly under load
        minTemp = 62; # °C — stay quiet until significant heat
        maxTemp = 75; # °C — reach full speed before hitting thermal limit
        minPwm = 64; # ~25% (was 15), absolute minimum (fans may stall)
        maxPwm = 178; # capped at 70% to reduce noise under load
        hysteresis = 5; # reduce fan speed oscillation
        interval = 2; # responsive polling
        allowStop = false; # fans never fully stop for safety
        minStartOverride = 150; # reliable spin-up from low PWM
        gpuPwmChannels = [ ]; # case fans follow CPU temperature
      };

      gpuFancontrol = {
        enable = true;
        # GPU fan stays silent at idle, ramps for load
        minTemp = 62; # °C — GPU fan quiet until significant heat
        maxTemp = 75; # °C — full speed well before throttle point
        minPwm = 15; # ~25% (was 15), absolute minimum
        maxPwm = 178; # capped at 70% for improved acoustics
        hysteresis = 5; # stability
      };
    };

    networking.firewall.interfaces.br0.allowedTCPPorts = lib.mkAfter [
      22 # sshd (key-only auth)
      80
      443
    ];

    # Install helper to toggle CPU boost quickly (cpu-boost {status|on|off|toggle})
    environment.systemPackages = lib.mkAfter [
      pkgs.openrgb # per-device RGB controller UI
      pkgs.rustup # Rust toolchain manager (rustc, cargo, rust-analyzer via rustup)
      pkgs.rust-analyzer # Rust LSP server
      (pkgs.writeShellScriptBin "cpu-boost" ''
        exec ${lib.getExe pkgs.neg.hwctl} cpu boost "$@"
      '') # CLI toggle for AMD Precision Boost
      (pkgs.writeShellScriptBin "fan-manual" ''
        exec ${lib.getExe pkgs.neg.hwctl} fan manual ''${1:-}
      '') # Switch fans to manual control
      (pkgs.writeShellScriptBin "fan-auto" ''
        exec ${lib.getExe pkgs.neg.hwctl} fan auto
      '') # Switch fans to automatic control
    ];
    servicesProfiles.avahi.services = [
      {
        name = "smb";
        type = "smb";
        port = 445;
        txtRecords = [
          "path=/zero/sync/smb"
          "share=shared"
        ];
      }
      {
        name = "afp";
        type = "afpovertcp";
        port = 548;
        txtRecords = [ "path=/zero/sync/smb" ];
      }
      {
        name = "nfs";
        type = "nfs";
        port = 2049;
        txtRecords = [ "path=/zero/sync/smb" ];
      }
      {
        name = "ssh";
        type = "ssh";
        port = 22;
      }
      {
        name = "sftp";
        type = "sftp-ssh";
        port = 22;
      }
      {
        name = "airplay";
        type = "airplay";
        port = 7000;
        txtRecords = [ "device=shairport-sync" ];
      }
      {
        name = "raop";
        type = "raop";
        port = 5000;
        txtRecords = [ "device=shairport-sync" ];
      }
    ];

    services = lib.mkMerge [
      {
        # dsh-ssh ssh_tunnel: with allowTcpForwarding enabled in
        # servicesProfiles.openssh above, restrict forwarded destinations to
        # loopback so the hardened sshd cannot be used as a pivot into the LAN.
        openssh.extraConfig = ''
          PermitOpen 127.0.0.1:* [::1]:*
        '';

        # Static host rewrites pushed into Unbound (served to AdGuard Home upstream)
        unbound.settings.server."local-data" = map (s: "\"${s}\"") unboundLocalData;

        # GNOME Tracker removed — pulls GTK, no search indexing needed

        # gnome-keyring — D-Bus Secret Service for browser cookie encryption (Vivaldi 8.x)
        gnome.gnome-keyring.enable = true;
        # Disable gcr SSH agent — conflicts with programs.ssh.startAgent, and we only
        # need gnome-keyring for its D-Bus Secret Service (browser cookie encryption).
        gnome.gcr-ssh-agent.enable = false;

        udev.packages = lib.mkAfter [ pkgs.openrgb ]; # Open source RGB lighting control
        power-profiles-daemon.enable = true;
        # Do not expose AdGuard Home Prometheus metrics on this host
        adguardhome.settings.prometheus.enabled = false;

        "shairport-sync" = {
          enable = true;
          openFirewall = true;
          settings.general = {
            name = "Odin AirPlay";
            output_backend = "pipewire";
          };
        };

        smartd.enable = false;

        # Persistent journald logs with retention and rate limiting
        journald = {
          storage = "persistent";
          extraConfig = ''
            SystemMaxUse=1G
            MaxRetentionSec=1month
            RateLimitIntervalSec=30s
            RateLimitBurst=1000
          '';
        };
        # Keep X11 off for this host
        xserver.enable = lib.mkForce false;

        # Resilio Sync (interactive Web UI, auth via SOPS)
        resilio = lib.mkIf (builtins.pathExists (inputs.self + "/secrets/resilio.sops.yaml")) {
          enable = false;

          # state / DB
          storagePath = "/zero/sync/.state";

          # data root (folders will live under this)
          directoryRoot = "/zero/sync";

          enableWebUI = true;
          httpListenAddr = "127.0.0.1";
          httpListenPort = 9000;

          # Actual credentials come from SOPS and are injected into config.json
          httpLogin = "placeholder_login";
          httpPass = "placeholder_pass";

          listeningPort = 41111;
          useUpnp = false;
        };

      }
    ];

    # (php-fpm settings)

    # Disable runtime logrotate check (build-time check remains). Avoids false negatives
    # when rotating files under non-standard paths or missing until first run.

    # Resilio Sync: Web UI auth via SOPS, data under /zero/sync
    sops.secrets."resilio/http-login" =
      lib.mkIf
        (builtins.pathExists (inputs.self + "/secrets/resilio.sops.yaml") && config.services.resilio.enable)
        {
          sopsFile = inputs.self + "/secrets/resilio.sops.yaml";
          owner = "rslsync";
          mode = "0400";
        };
    sops.secrets."resilio/http-pass" =
      lib.mkIf
        (builtins.pathExists (inputs.self + "/secrets/resilio.sops.yaml") && config.services.resilio.enable)
        {
          sopsFile = inputs.self + "/secrets/resilio.sops.yaml";
          owner = "rslsync";
          mode = "0400";
        };

    environment.variables.GAME_PIN_AUTO_LIMIT = "8"; # Limit auto-picked V-Cache CPU set size for game-run pinning

    # The dsh web terminal (dsh-terminal-bash / better-sidebar) spawns
    # /bin/bash as its fallback shell. That symlink is not managed by NixOS:
    # a store GC of the old bash leaves it dangling and the web terminal
    # dies with "execvp(3) failed: No such file or directory". Keep it
    # pointed at the live system shell on every activation.
    system.activationScripts.binBash = lib.stringAfter [ "users" ] ''
      ln -sfn /run/current-system/sw/bin/bash /bin/bash
    '';

    systemd = {
      # Ensure auxiliary data directories exist with correct ownership
      tmpfiles.rules = lib.mkAfter (
        [
          "d /zero/sync/upload-next 0755 neg neg - -"
        ]
        ++
          lib.optionals
            (builtins.pathExists (inputs.self + "/secrets/resilio.sops.yaml") && config.services.resilio.enable)
            [
              # Resilio state / license storage (service runs as rslsync)
              "d /zero/sync/.state 0700 rslsync rslsync - -"
            ]
      );
      services = {
        # Power saving by default for less heat/noise
        "power-profiles-default" = {
          description = "Set default power profile to balanced";
          after = [ "power-profiles-daemon.service" ];
          wants = [ "power-profiles-daemon.service" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "/run/current-system/sw/bin/powerprofilesctl set balanced";
          };
          # Defer to post-boot to avoid interfering with activation and to follow repo policy
          wantedBy = [ "graphical.target" ];
        };

        # Disable runtime logrotate check (build-time check remains). Avoids false negatives
        # when rotating files under non-standard paths or missing until first run.
        logrotate-checkconf.enable = false;

        # Inject Resilio Web UI credentials from SOPS into generated config.json
        resilio =
          lib.mkIf
            (builtins.pathExists (inputs.self + "/secrets/resilio.sops.yaml") && config.services.resilio.enable)
            {
              serviceConfig.ExecStartPre = lib.mkAfter [ resilioAuthScript ];
            };
      };

    };
  }
  (lib.mkIf (builtins.pathExists (inputs.self + "/secrets/odin-wireguard-wg-quick.sops")) {
    # On-demand WireGuard VPN for odin, configured via wg-quick config stored in sops.
    # The tunnel is not started automatically; use systemctl start/stop to control it.
    sops.secrets."wireguard/odin-wg-quick" = {
      sopsFile = inputs.self + "/secrets/odin-wireguard-wg-quick.sops";
      format = "binary"; # keep original wg-quick config format
      owner = "root";
      group = "root";
      mode = "0600";
    };

    systemd.services."wg-quick-vpn-odin" = {
      description = "On-demand WireGuard VPN (odin, wg-quick)";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ ]; # do not autostart; manual systemctl only
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${lib.getExe' pkgs.wireguard-tools "wg-quick"} up ${
          # Tools for the WireGuard secure network tunnel
          config.sops.secrets."wireguard/odin-wg-quick".path
        }";
        ExecStop = "${lib.getExe' pkgs.wireguard-tools "wg-quick"} down ${
          # Tools for the WireGuard secure network tunnel
          config.sops.secrets."wireguard/odin-wg-quick".path
        }";
      };
    };
  })
  (lib.mkIf (config.lib.neg.enabled "virt.docker") {
    environment.systemPackages = [ pkgs.docker-compose ]; # container orchestration CLI (Docker Compose)
  })

  # Minimal Telegram alert stack for this host:
  #   - Prometheus Alertmanager (routes alerts, webhook to the bridge);
  #   - telegram-alert-bridge: 127.0.0.1:9094 -> Telegram Bot API;
  #   - telegram-alert-scanner: every minute, failed units / OOM kills /
  #     sshd brute-force attempts -> Alertmanager.
  # Everything is gated on secrets/telegram.sops.yaml existing; without the
  # secret file the whole stack stays disabled (same pattern as resilio).
  (lib.mkIf (builtins.pathExists (inputs.self + "/secrets/telegram.sops.yaml")) {
    monitoring.alertmanager.enable = true;

    sops.secrets."telegram/bot-token" = {
      sopsFile = inputs.self + "/secrets/telegram.sops.yaml";
      key = "bot-token";
      owner = "root";
      mode = "0400";
    };
    sops.secrets."telegram/chat-id" = {
      sopsFile = inputs.self + "/secrets/telegram.sops.yaml";
      key = "chat-id";
      owner = "root";
      mode = "0400";
    };

    systemd.services."telegram-alert-bridge" = {
      description = "Alertmanager Telegram webhook bridge";
      documentation = [
        "https://prometheus.io/docs/alerting/latest/configuration/#webhook_config"
      ];
      after = [
        "network-online.target"
        "alertmanager.service"
      ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        ExecStart = "${lib.getExe telegramBridgeScript}";
        Restart = "on-failure";
        RestartSec = 5;
      };
    };

    systemd.services."telegram-alert-scanner" = {
      description = "Scan failed units, OOM kills and sshd brute-force attempts into Alertmanager";
      after = [ "alertmanager.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 ${telegramAlertScannerScript}";
        Restart = "on-failure";
        RestartSec = 10;
        # Journal access requires root; StateDirectory keeps the
        # snapshot/cursor files under /var/lib/telegram-alert-scanner.
        StateDirectory = "telegram-alert-scanner";
      };
    };

    systemd.timers."telegram-alert-scanner" = {
      description = "Run the Telegram alert scanner every minute";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* *:*:00";
        Unit = "telegram-alert-scanner.service";
      };
    };
  })
]
