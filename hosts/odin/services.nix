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
in
lib.mkMerge [
  {
    # Primary user (single source of truth for name/ids)
    users.main = {
      name = "neg";
      uid = 1000;
      gid = 1000;
      description = "Neg";
    };
    # Host-specific feature toggles
    features.dev.ai.opencode.enable = lib.mkForce false; # TEMP: npm install hangs
    features.dev.ai.omp.enable = true; # Oh My Pi (omp) — AI coding agent fork with LSP, DAP, subagents
    features.dev.ai.pi.enable = true;
    features.cli.broot.enable = true;
    features.dev.tla.enable = true;
    features.hardware.usbAutomount.enable = true;
    features.net.tailscale.enable = true;
    features.input.warpd.enable = true; # warpd: keyboard-driven pointer control

    # Roles enabled for this host
    roles = {
      workstation.enable = true;
      homelab.enable = true;
      media.enable = true;
      monitoring.enable = true;
    };

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
      # Local DNS rewrites for LAN names (service enable comes from roles)
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
      # Run a Bitcoin Core node with data stored under /zero/bitcoin-node
      # Temporarily disabled
      bitcoind = {
        enable = false;
        dataDir = "/zero/bitcoin-node";
      };
      duckdns = lib.mkIf (builtins.pathExists (inputs.self + "/secrets/duckdns.env.sops")) {
        enable = true;
        domain = "${config.networking.hostName}.duckdns.org";
        environmentFile = config.sops.secrets."duckdns/env".path;
        ipv6 = {
          enable = false;
          device = "net1";
        };
      };
      # Wyoming OpenAI proxy — bridges Wyoming protocol with OpenAI-compatible STT/TTS
      # Uncomment and configure to enable:
      # wyoming-openai = {
      #   enable = true;
      #   stt = {
      #     enable = true;
      #     key = "...";  # Or use SOPS secret + environment file
      #     url = "https://api.openai.com/v1";
      #     models = [ "whisper-1" "gpt-4o-transcribe" ];
      #     streamingModels = [ "gpt-4o-transcribe" ];
      #   };
      #   tts = {
      #     enable = true;
      #     key = "...";
      #     url = "https://api.openai.com/v1";
      #     models = [ "tts-1" "gpt-4o-mini-tts" ];
      #     voices = [ "alloy" "echo" "fable" "onyx" "nova" "shimmer" ];
      #     streamingModels = [ "tts-1" ];
      #   };
      # };
    };
    # Static host rewrites pushed into Unbound (served to AdGuard Home upstream)

    monitoring = lib.mkIf config.roles.monitoring.enable {
      netdata.enable = false; # Disable Netdata on this host
      logs.enable = false; # Disable centralized logs (Loki + Promtail) for this host
      grafana = {
        enable = false;
      }; # Keep Grafana wiring available but disabled on this host
    };

    # Disable RNNoise virtual mic for this host by default
    hardware.audio.rnnoise.enable = false;

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
      # pkgs.neg.term39 # term39 commented out — clang-sys build failure, fix separately
    ];
    servicesProfiles.avahi.services = [
      { name = "smb";    type = "smb";        port = 445;  txtRecords = [ "path=/zero/sync/smb" "share=shared" ]; }
      { name = "afp";    type = "afpovertcp"; port = 548;  txtRecords = [ "path=/zero/sync/smb" ]; }
      { name = "nfs";    type = "nfs";        port = 2049; txtRecords = [ "path=/zero/sync/smb" ]; }
      { name = "ssh";    type = "ssh";        port = 22; }
      { name = "sftp";   type = "sftp-ssh";   port = 22; }
      { name = "airplay"; type = "airplay";   port = 7000; txtRecords = [ "device=shairport-sync" ]; }
      { name = "raop";   type = "raop";       port = 5000; txtRecords = [ "device=shairport-sync" ]; }
    ];

    services = lib.mkMerge [
      {
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
        # Remove SDDM/Plasma additions; keep Hyprland-only setup
        # Temporarily disable Ollama on this host
        ollama.enable = false;
        # GVFS disabled — pulls GTK; re-enable if file manager needs MTP/SMB
        # gvfs.enable = true;

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

        # Bitcoind instance is now managed by modules/servers/bitcoind
      }
    ];

    # (php-fpm settings)


    # Disable runtime logrotate check (build-time check remains). Avoids false negatives
    # when rotating files under non-standard paths or missing until first run.

    # DuckDNS token (EnvironmentFile with DUCKDNS_TOKEN)
    sops.secrets."duckdns/env" =
      lib.mkIf (builtins.pathExists (inputs.self + "/secrets/duckdns.env.sops"))
        {
          sopsFile = inputs.self + "/secrets/duckdns.env.sops";
          format = "dotenv";
          owner = "root";
          mode = "0400";
        };

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
  (lib.mkIf (config.features.virt.docker.enable or false) {
    environment.systemPackages = [ pkgs.docker-compose ]; # container orchestration CLI (Docker Compose)
  })
]
