{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:
let
  grafanaEnabled = config.services.grafana.enable or false;
  hasResilioSecret = builtins.pathExists (inputs.self + "/secrets/resilio.sops.yaml");
  wireguardSopsFile = inputs.self + "/secrets/telfir-wireguard-wg-quick.sops";
  duckdnsEnvSecret = inputs.self + "/secrets/duckdns.env.sops";
  hasDuckdnsSecret = builtins.pathExists duckdnsEnvSecret;
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

    ${pkgs.gnused}/bin/sed -i "s|placeholder_login|$LOGIN|" "$CONFIG_FILE" # GNU sed, a batch stream editor
    ${pkgs.gnused}/bin/sed -i "s|placeholder_pass|$PASS|" "$CONFIG_FILE" # GNU sed, a batch stream editor
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
    features.dev.ai.enable = true;
    features.dev.ai.antigravity.enable = true;
    features.dev.ai.opencode.enable = true;
    features.text.tex.enable = false;
    features.cli.broot.enable = true;
    features.cli.yazi.enable = true;
    features.dev.tla.enable = true;
    features.apps.winapps.enable = false;
    features.apps.libreoffice.enable = false;
    features.games.launchers.lutris.enable = false;
    features.games.launchers.prismlauncher.enable = false;
    features.games.launchers.heroic.enable = false;
    features.games.nethack.enable = true;
    features.emulators.retroarch.enable = false;
    features.gui.hy3.enable = true;
    features.gui.walker.enable = false;
    features.gui.quickshell.enable = true;
    features.hardware.usbAutomount.enable = true;
    features.net.tailscale.enable = true;
    features.web.firefox.enable = false;

    features.dev.openxr = {
      enable = false;
      envision.enable = false;
      runtime.service.enable = true;
    };

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

    # Enable Docker engine for WinBoat and use real docker socket
    #     virtualisation = {
    #       docker.enable = true;
    #       podman = {
    #         dockerCompat = lib.mkForce false;
    #         dockerSocket.enable = lib.mkForce false;
    #       };
    #     };

    # Remove experimental mpv OpenVR overlay

    # Service profiles toggles for this host
    servicesProfiles = {
      # Local DNS rewrites for LAN names (service enable comes from roles)
      adguardhome.rewrites = [
        {
          domain = "telfir";
          answer = "192.168.2.240";
        }
        {
          domain = "telfir.local";
          answer = "192.168.2.240";
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
      # Explicitly override media role to keep Jellyfin off on this host
      jellyfin.enable = false;
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
      duckdns = lib.mkIf hasDuckdnsSecret {
        enable = true;
        domain = "${config.networking.hostName}.duckdns.org";
        environmentFile = config.sops.secrets."duckdns/env".path;
        ipv6 = {
          enable = false;
          device = "net1";
        };
      };
    };
    # Static host rewrites pushed into Unbound (served to AdGuard Home upstream)

    monitoring = {
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
      pkgs.winboat # Windows VM support
      pkgs.openrgb # per-device RGB controller UI
      (pkgs.writeShellScriptBin "cpu-boost" (
        builtins.readFile (inputs.self + "/scripts/hw/cpu-boost.sh")
      )) # CLI toggle for AMD Precision Boost
      (pkgs.writeShellScriptBin "fan-manual" (
        builtins.readFile (inputs.self + "/scripts/hw/fan-manual.sh")
      )) # Switch fans to manual control
      (pkgs.writeShellScriptBin "fan-auto" (builtins.readFile (inputs.self + "/scripts/hw/fan-auto.sh"))) # Switch fans to automatic control
    ];
    environment.etc = {
      "avahi/services/smb.service".text = ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h SMB share</name>
          <service>
            <type>_smb._tcp</type>
            <port>445</port>
            <txt-record>path=/zero/sync/smb</txt-record>
            <txt-record>share=shared</txt-record>
          </service>
        </service-group>
      '';
      "avahi/services/afp.service".text = ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h AFP share</name>
          <service>
            <type>_afpovertcp._tcp</type>
            <port>548</port>
            <txt-record>path=/zero/sync/smb</txt-record>
          </service>
        </service-group>
      '';
      "avahi/services/nfs.service".text = ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h NFS export</name>
          <service>
            <type>_nfs._tcp</type>
            <port>2049</port>
            <txt-record>path=/zero/sync/smb</txt-record>
          </service>
        </service-group>
      '';
      "avahi/services/ssh.service".text = ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h SSH</name>
          <service>
            <type>_ssh._tcp</type>
            <port>22</port>
          </service>
        </service-group>
      '';
      "avahi/services/sftp.service".text = ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h SFTP</name>
          <service>
            <type>_sftp-ssh._tcp</type>
            <port>22</port>
          </service>
        </service-group>
      '';
      "avahi/services/airplay.service".text = ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h AirPlay</name>
          <service>
            <type>_airplay._tcp</type>
            <port>7000</port>
            <txt-record>device=shairport-sync</txt-record>
          </service>
        </service-group>
      '';
      "avahi/services/raop.service".text = ''
        <?xml version="1.0" standalone='no'?>
        <!DOCTYPE service-group SYSTEM "avahi-service.dtd">
        <service-group>
          <name replace-wildcards="yes">%h RAOP</name>
          <service>
            <type>_raop._tcp</type>
            <port>5000</port>
            <txt-record>device=shairport-sync</txt-record>
          </service>
        </service-group>
      '';
    };

    services = lib.mkMerge [
      {
        ncps = {
          enable = true;
          cache = {
            hostName = "cache.example.com";
            dataPath = "/zero/ncps";
            tempPath = "/zero/ncps-temp";
            maxSize = "150G";
          };
          upstream = {
            caches = [ "https://cache.nixos.org" ];
            publicKeys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
          };
        };

        # Static host rewrites pushed into Unbound (served to AdGuard Home upstream)
        unbound.settings.server."local-data" = map (s: "\"${s}\"") unboundLocalData;

        gnome = {
          localsearch.enable = true;
          tinysparql.enable = true;
        };

        udev.packages = lib.mkAfter [ pkgs.openrgb ]; # Open source RGB lighting control
        power-profiles-daemon.enable = true;
        # Do not expose AdGuard Home Prometheus metrics on this host
        adguardhome.settings.prometheus.enabled = false;

        "shairport-sync" = {
          enable = true;
          openFirewall = true;
          settings.general = {
            name = "Telfir AirPlay";
            output_backend = "pw";
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
        # Keep Plasma/X11 off for this host
        desktopManager.plasma6.enable = lib.mkForce false;
        xserver.enable = lib.mkForce false;
        # Remove SDDM/Plasma additions; keep Hyprland-only setup
        # Temporarily disable Ollama on this host
        ollama.enable = false;
        # Avoid port conflicts: ensure nginx is disabled when using Caddy
        nginx.enable = false;

        # Enable GVFS (virtual filesystem) support for file managers (MTP, SMB, etc.)
        gvfs.enable = true;

        # Resilio Sync (interactive Web UI, auth via SOPS)
        resilio = lib.mkIf hasResilioSecret {
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
      (lib.mkIf grafanaEnabled {
        # Harden Grafana: avoid external calls and too-frequent refreshes
        grafana.settings = {
          analytics = {
            reporting_enabled = false;
            check_for_updates = false;
          };
          users = {
            # Do not fetch avatars from Gravatar (external egress from clients/Server)
            allow_gravatar = false;
          };
          news.news_feed_enabled = false;
          dashboards.min_refresh_interval = "10s";
          snapshots.external_enabled = false;
          # Conservative plugin settings (no alpha, keep install API default)
          plugins = {
            enable_alpha = false;
            disable_install_api = true;
          };
        };

        # (Grafana env + tmpfiles rules are defined at top-level below)

        # Provision local dashboards (Unbound)
        grafana.provision.dashboards.settings.providers = lib.mkAfter [
          {
            name = "local-json";
            orgId = 1;
            type = "file";
            disableDeletion = false;
            editable = true;
            options.path = inputs.self + "/files/dashboards";
          }
        ];
      })
    ];

    # (php-fpm settings)

    # Bitcoind minimal metrics → node_exporter textfile collector
    # Exposes:
    #   bitcoin_block_height{instance="main",chain="<chain>"} <n>
    #   bitcoin_headers{instance="main",chain="<chain>"} <n>
    #   bitcoin_time_since_last_block_seconds{instance} <seconds>
    #   bitcoin_peers_connected{instance} <n>
    # Directory for textfile collector is ensured above via tmpfiles rules

    # Periodic metric collection service + timer
    # Firewall port for bitcoind is opened by the bitcoind server module

    # Disable runtime logrotate check (build-time check remains). Avoids false negatives
    # when rotating files under non-standard paths or missing until first run.

    # DuckDNS token (EnvironmentFile with DUCKDNS_TOKEN)
    sops.secrets."duckdns/env" = lib.mkIf hasDuckdnsSecret {
      sopsFile = duckdnsEnvSecret;
      format = "dotenv";
      owner = "root";
      mode = "0400";
    };

    # Resilio Sync: Web UI auth via SOPS, data under /zero/sync
    sops.secrets."resilio/http-login" = lib.mkIf (hasResilioSecret && config.services.resilio.enable) {
      sopsFile = inputs.self + "/secrets/resilio.sops.yaml";
      owner = "rslsync";
      mode = "0400";
    };
    sops.secrets."resilio/http-pass" = lib.mkIf (hasResilioSecret && config.services.resilio.enable) {
      sopsFile = inputs.self + "/secrets/resilio.sops.yaml";
      owner = "rslsync";
      mode = "0400";
    };

    # Avoid forcing pkexec as setuid; Steam/SteamVR misbehaves when invoked with elevated EUID.
    # Use polkit rules if specific privileges are required instead of global setuid pkexec.

    # Games autoscale defaults for this host
    profiles.games = {
      autoscaleDefault = false;
      targetFps = 240;
      nativeBaseFps = 240;
    };

    environment.variables.GAME_PIN_AUTO_LIMIT = "8"; # Limit auto-picked V-Cache CPU set size for game-run pinning
    dev.gcc.autofdo.enable = false; # AutoFDO tooling disabled on this host (module kept)

    systemd = {
      # Ensure auxiliary data directories exist with correct ownership
      tmpfiles.rules = lib.mkAfter [
        # Resilio state / license storage (service runs as rslsync)
        "d /zero/sync/.state 0700 rslsync rslsync - -"
        "d /zero/sync/upload-next 0755 neg neg - -"
        # NCPS storage
        "d /zero/ncps 0750 ncps ncps - -"
        "d /zero/ncps-temp 0750 ncps ncps - -"
      ];
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

        # Periodic metric collection service + timer
        "bitcoind-textfile-metrics" =
          let
            bitcoindInstance = config.servicesProfiles.bitcoind.instance or "main";
            bitcoindUser = "bitcoind-${bitcoindInstance}";
            dataDir = config.servicesProfiles.bitcoind.dataDir or "/var/lib/bitcoind/${bitcoindInstance}";
            textfileDir = "/var/lib/node_exporter/textfile_collector";
            metricsFile = "${textfileDir}/bitcoind_${bitcoindInstance}.prom";
            metricsScript = pkgs.writeShellScript "bitcoind-textfile-metrics.sh" ''
              set -euo pipefail
              TMPFILE="$(mktemp)"
              ts() { date +%s; }

              CLI="${pkgs.bitcoind}/bin/bitcoin-cli -datadir ${lib.escapeShellArg dataDir}"

              # Basic info (avoid heavy calls)
              blocks=$($CLI getblockcount 2>/dev/null || echo 0)
              # headers and chain via blockchaininfo
              info=$($CLI getblockchaininfo 2>/dev/null || echo '{}')
              headers=$(printf '%s\n' "$info" | ${pkgs.jq}/bin/jq -r '.headers // 0' 2>/dev/null || echo 0) # Lightweight and flexible command-line JSON processor
              chain=$(printf '%s\n' "$info" | ${pkgs.jq}/bin/jq -r '.chain // "unknown"' 2>/dev/null || echo unknown) # Lightweight and flexible command-line JSON processor

              # Determine best block time for staleness metric
              besthash=$($CLI getbestblockhash 2>/dev/null || echo)
              if [ -n "$besthash" ]; then
                block_time=$($CLI getblockheader "$besthash" 2>/dev/null | ${pkgs.jq}/bin/jq -r '.time // 0' 2>/dev/null || echo 0) # Lightweight and flexible command-line JSON processor
              else
                block_time=0
              fi
              now=$(ts)
              if [ "$block_time" -gt 0 ] 2>/dev/null; then
                since=$(( now - block_time ))
              else
                since=0
              fi

              # Peer connections
              peers=$($CLI getnetworkinfo 2>/dev/null | ${pkgs.jq}/bin/jq -r '.connections // 0' 2>/dev/null || echo 0) # Lightweight and flexible command-line JSON processor

              cat > "$TMPFILE" <<EOF
              # HELP bitcoin_block_height Current block height as reported by bitcoind
              # TYPE bitcoin_block_height gauge
              bitcoin_block_height{instance="${bitcoindInstance}",chain="$chain"} $blocks
              # HELP bitcoin_headers Current header height as reported by bitcoind
              # TYPE bitcoin_headers gauge
              bitcoin_headers{instance="${bitcoindInstance}",chain="$chain"} $headers
              # HELP bitcoin_time_since_last_block_seconds Seconds since the best block time
              # TYPE bitcoin_time_since_last_block_seconds gauge
              bitcoin_time_since_last_block_seconds{instance="${bitcoindInstance}"} $since
              # HELP bitcoin_peers_connected Number of peer connections
              # TYPE bitcoin_peers_connected gauge
              bitcoin_peers_connected{instance="${bitcoindInstance}"} $peers
              EOF

              install -m 0644 -D "$TMPFILE" ${lib.escapeShellArg metricsFile}
              rm -f "$TMPFILE"
            '';
          in
          {
            enable = false;
            description = "Export bitcoind minimal metrics to node_exporter textfile collector";
            serviceConfig = {
              Type = "oneshot";
              User = bitcoindUser;
              Group = bitcoindUser;
              ExecStart = metricsScript;
            };
            wants = [ "bitcoind-${bitcoindInstance}.service" ];
            after = [ "bitcoind-${bitcoindInstance}.service" ];
          };

        # Disable runtime logrotate check (build-time check remains). Avoids false negatives
        # when rotating files under non-standard paths or missing until first run.
        logrotate-checkconf.enable = false;

        # Inject Resilio Web UI credentials from SOPS into generated config.json
        resilio = lib.mkIf (hasResilioSecret && config.services.resilio.enable) {
          serviceConfig.ExecStartPre = lib.mkAfter [ resilioAuthScript ];
        };
      };

      timers."bitcoind-textfile-metrics" = {
        enable = false;
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = "2m";
          OnUnitActiveSec = "30s";
          AccuracySec = "5s";
          Unit = "bitcoind-textfile-metrics.service";
        };
      };
    };

    # Configure Nix to use the local NCPS cache
    nix.settings = {
      substituters = lib.mkForce [
        "http://127.0.0.1:8501"
        "https://cache.nixos.org"
      ];
      trusted-public-keys = [
        "cache.example.com:bBR/xna7TbBMPQnlakT/cuLs6b/J4afpXhNJfjcFM+k="
      ];
    };
  }
  (lib.mkIf grafanaEnabled {
    systemd = {
      services.grafana = {
        # Disable preinstall/auto-update feature toggle explicitly via env (Grafana 10/11/12)
        environment = {
          GF_FEATURE_TOGGLES_DISABLE = "preinstallAutoUpdate";
        };

        # Restrict Grafana network egress to loopback only.
        # Caddy proxies from LAN to 127.0.0.1, and datasources (Loki/Prometheus) are local.
        # This blocks accidental outbound calls (updates, gravatar, external plugins, etc.).
        serviceConfig = {
          IPAddressDeny = "any";
          IPAddressAllow = [
            "127.0.0.0/8"
            "::1/128"
          ];
        };
      };

      # Ensure plugins directory is clean on activation
      tmpfiles.rules = lib.mkAfter [
        "R /var/lib/grafana/plugins - - - - -"
        "d /var/lib/grafana/plugins 0750 grafana grafana - -"
      ];
    };

    # SOPS secret for Grafana admin password
    sops.secrets."grafana/admin_password" =
      let
        yaml = inputs.self + "/secrets/grafana-admin-password.sops.yaml";
        bin = inputs.self + "/secrets/grafana-admin-password.sops";
      in
      lib.mkIf (builtins.pathExists yaml || builtins.pathExists bin) {
        sopsFile = if builtins.pathExists yaml then yaml else bin;
        format = "binary"; # provide plain string to $__file provider
        # Ensure grafana can read the secret when referenced via $__file{}
        owner = "grafana";
        group = "grafana";
        mode = "0400";
        # Restart Grafana if the secret changes
        restartUnits = [ "grafana.service" ];
      };
  })
  (lib.mkIf (builtins.pathExists wireguardSopsFile) {
    # On-demand WireGuard VPN for telfir, configured via wg-quick config stored in sops.
    # The tunnel is not started automatically; use systemctl start/stop to control it.
    sops.secrets."wireguard/telfir-wg-quick" = {
      sopsFile = wireguardSopsFile;
      format = "binary"; # keep original wg-quick config format
      owner = "root";
      group = "root";
      mode = "0600";
    };

    systemd.services."wg-quick-vpn-telfir" = {
      description = "On-demand WireGuard VPN (telfir, wg-quick)";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ ]; # do not autostart; manual systemctl only
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.wireguard-tools}/bin/wg-quick up ${
          # Tools for the WireGuard secure network tunnel
          config.sops.secrets."wireguard/telfir-wg-quick".path
        }";
        ExecStop = "${pkgs.wireguard-tools}/bin/wg-quick down ${
          # Tools for the WireGuard secure network tunnel
          config.sops.secrets."wireguard/telfir-wg-quick".path
        }";
      };
    };
  })
  (lib.mkIf (config.features.virt.docker.enable or false) {
    environment.systemPackages = [ pkgs.docker-compose ];
  })
  {
    systemd.services.ncps.serviceConfig.ExecStartPre = lib.mkForce [
      (pkgs.writeShellScript "ncps-init-db" ''
        ${pkgs.dbmate}/bin/dbmate \
          --migrations-dir=${
            pkgs.fetchFromGitHub {
              owner = "kalbasit";
              repo = "ncps";
              rev = "935417859d2671290be8a8f4722e6cd1925dc41f";
              sha256 = "0ib819jiz0jq9xhzg8k75mv7qkmkb01yjjfzcj1v515f9if95ypf";
            }
          }/db/migrations/sqlite \
          --url=sqlite:/zero/ncps/db/db.sqlite up
      '')
    ];
  }
]
