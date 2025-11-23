{
  lib,
  config,
  pkgs,
  inputs,
  ...
}: let
  grafanaEnabled = config.services.grafana.enable or false;
  hasResilioSecret = builtins.pathExists (inputs.self + "/secrets/resilio.sops.yaml");
  resilioFsSetupScript = pkgs.writeShellScript "resilio-fs-setup" ''
    set -euo pipefail
    DATA_ROOT="/zero/sync"
    STATE_DIR="/zero/sync/.state"

    # Ensure data and state directories exist with correct owner/group and setgid on data root
    mkdir -p "$DATA_ROOT" "$STATE_DIR"
    chown rslsync:rslsync "$DATA_ROOT" "$STATE_DIR"
    chmod 2770 "$DATA_ROOT"
    chmod 700 "$STATE_DIR"

    # Ensure existing share directories under /zero/sync (except .state) are group-writable
    for d in "$DATA_ROOT"/*; do
      [ -d "$d" ] || continue
      [ "$d" = "$STATE_DIR" ] && continue
      chgrp rslsync "$d" || true
      chmod 2770 "$d" || true
    done

    # Best-effort ACLs to keep group rslsync rwx regardless of umask
    if command -v ${pkgs.acl}/bin/setfacl >/dev/null 2>&1; then
      ${pkgs.acl}/bin/setfacl -d -m group:rslsync:rwx "$DATA_ROOT" || true
      ${pkgs.acl}/bin/setfacl -m group:rslsync:rwx "$DATA_ROOT" || true
      for d in "$DATA_ROOT"/*; do
        [ -d "$d" ] || continue
        [ "$d" = "$STATE_DIR" ] && continue
        ${pkgs.acl}/bin/setfacl -m group:rslsync:rwx "$d" || true
      done
    fi
  '';
  resilioAuthScript = pkgs.writeShellScript "resilio-set-webui-auth" ''
    set -euo pipefail
    CONFIG="/run/rslsync/config.json"
    USER_FILE="${config.sops.secrets."resilio/http-login".path}"
    PASS_FILE="${config.sops.secrets."resilio/http-pass".path}"

    if [ ! -r "$USER_FILE" ] || [ ! -r "$PASS_FILE" ]; then
      echo "resilio-set-webui-auth: secret files not readable, skipping" >&2
      exit 0
    fi

    USER="$(tr -d '\n' < "$USER_FILE")"
    PASS="$(tr -d '\n' < "$PASS_FILE")"

    if [ -z "$USER" ] || [ -z "$PASS" ]; then
      echo "resilio-set-webui-auth: empty user/pass, skipping" >&2
      exit 0
    fi

    if [ ! -f "$CONFIG" ]; then
      echo "resilio-set-webui-auth: $CONFIG not found, skipping" >&2
      exit 0
    fi

    tmp="$(mktemp)"
    ${pkgs.jq}/bin/jq \
      --arg user "$USER" \
      --arg pass "$PASS" \
      ' .webui = (.webui // {}) 
        | .webui.login = $user
        | .webui.password = $pass ' \
      "$CONFIG" > "$tmp"
    mv "$tmp" "$CONFIG"
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
      features.apps.winapps.enable = true;
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
      virtualisation = {
        docker.enable = true;
        podman = {
          dockerCompat = lib.mkForce false;
          dockerSocket.enable = lib.mkForce false;
        };
      };

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
        # Disable Samba profile on this host
        samba.enable = false;
        # Run a Bitcoin Core node with data stored under /zero/bitcoin-node
        # Temporarily disabled
        bitcoind = {
          enable = false;
          dataDir = "/zero/bitcoin-node";
        };
      };

      monitoring = {
        # Disable Netdata on this host (keep other monitoring like sysstat)
        netdata.enable = false;
        # Disable centralized logs (Loki + Promtail) for this host
        logs.enable = false;
        # Keep Grafana wiring available but disabled on this host
        grafana = {
          enable = false;
          port = 3030;
          # Serve Grafana only via Caddy: bind to localhost and do not open the port
          listenAddress = "127.0.0.1";
          openFirewall = false;
          firewallInterfaces = ["br0"];
          # Admin via SOPS secret (if present)
          adminUser = "admin";
          # Point to the SOPS-managed file below (only when the secret is defined)
          adminPasswordFile =
            lib.attrByPath
            ["sops" "secrets" "grafana/admin_password" "path"]
            null
            config;
          # HTTPS via Caddy on grafana.telfir
          caddyProxy = {
            enable = true;
            domain = "grafana.telfir";
            tlsInternal = true;
            openFirewall = true;
            firewallInterfaces = ["br0"];
          };
        };
      };

      # Disable RNNoise virtual mic for this host by default
      hardware.audio.rnnoise.enable = false;

      # Quiet fan profile: load nct6775 and autogenerate fancontrol config
      hardware.cooling = {
        enable = true;
        autoFancontrol = {
          enable = true;
          # Late start for quieter idle while still letting fans reach near-max PWM quickly.
          minTemp = 55; # °C — fans begin speeding up only after meaningful CPU heat
          maxTemp = 84; # °C — reach full sweep near high 80s to tame load spikes
          minPwm = 95; # 0–255, maintains a light baseline without stopping
          maxPwm = 250; # almost full PWM; bump to 255 if needed
          hysteresis = 4; # moderate hysteresis for stability
          interval = 2; # poll sensors more frequently during ramp-up
          allowStop = false; # CPU/case fans never idle below minPwm
          minStartOverride = 150; # ensures a confident spin-up from idle
          gpuPwmChannels = [2 3]; # case fans follow GPU temperature
        };
        gpuFancontrol = {
          enable = true;
          # GPU fan starts later but retains headroom at the top end.
          minTemp = 65; # °C — GPU fan stays low until substantial heat
          maxTemp = 90; # °C — push close to the limit once it reaches 90
          minPwm = 85; # 0–255, baseline spin to avoid stops
          maxPwm = 245; # near-maximum; raise to 255 if you want all-in cooling
          hysteresis = 4; # reduce chatter between steps
        };
      };

      # Install helper to toggle CPU boost quickly (cpu-boost {status|on|off|toggle})
      environment.systemPackages = lib.mkAfter [
        pkgs.winboat
        pkgs.docker-compose
        pkgs.openrgb # per-device RGB controller UI
        (pkgs.writeShellScriptBin "cpu-boost" (builtins.readFile (inputs.self + "/scripts/cpu-boost.sh"))) # CLI toggle for AMD Precision Boost
        (pkgs.writeShellScriptBin "fan-stop-capability-test" (builtins.readFile (inputs.self + "/scripts/fan-stop-capability-test.sh"))) # helper to test fan stop thresholds
      ];

      # Nextcloud via Caddy on LAN, served as "telfir"
      services = let
        devicesList = [
          {
            name = "telfir";
            id = "EZG57BT-TANWJ2R-QDVLV5X-4DKP7GU-HQENUT7-MA43GUU-AV3IN6P-7KKGZA3";
          }
        ];
        devices = builtins.listToAttrs (
          map (d: {
            inherit (d) name;
            value = {inherit (d) id;};
          })
          devicesList
        );
        foldersList = [
          {
            name = "music-upload";
            path = "/zero/syncthing/music-upload";
            devices = ["telfir"];
          }
          {
            name = "picture-upload";
            path = "/zero/syncthing/picture-upload";
            devices = ["telfir"];
          }
        ];
        folders = builtins.listToAttrs (
          map (f: {
            inherit (f) name;
            value = {inherit (f) path devices;};
          })
          foldersList
        );
      in
        lib.mkMerge [
          {
            udev.packages = lib.mkAfter [pkgs.openrgb];
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
            nextcloud = {
              hostName = "telfir";
              caddyProxy.enable = true;
            };
            caddy.email = "serg.zorg@gmail.com";

            # Prometheus stack removed on this host (server, exporters, alertmanager)

            # Syncthing host-specific devices and folders
            syncthing = {
              overrideDevices = true;
              overrideFolders = true;
              settings = {
                inherit devices folders;
                # Expose Syncthing GUI on all interfaces (port 8384)
                gui.address = "0.0.0.0:8384";
              };
            };
            # Resilio Sync (interactive Web UI, auth via SOPS)
            resilio = lib.mkIf hasResilioSecret {
              enable = true;

              # state / DB
              storagePath = "/zero/sync/.state";

              # data root (folders will live under this)
              directoryRoot = "/zero/sync";

              enableWebUI = true;
              httpListenAddr = "127.0.0.1";
              httpListenPort = 9000;

              # Actual credentials come from SOPS and are injected into config.json
              httpLogin = "placeholder";
              httpPass = "placeholder";

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

            # Provision local dashboards (Unbound, Nextcloud)
            grafana.provision.dashboards.settings.providers = lib.mkAfter [
              {
                name = "local-json";
                orgId = 1;
                type = "file";
                disableDeletion = false;
                editable = true;
                options.path = inputs.self + "/dashboards";
              }
            ];
          })
        ];

      # Provide GUI password to Syncthing from SOPS secret and set it at service start
      # - Secret file: secrets/syncthing.sops.yaml (key: syncthing/gui-pass)
      # - Make it readable by the Syncthing user and apply via ExecStartPre
      sops.secrets."syncthing/gui-pass" = lib.mkIf (builtins.pathExists (inputs.self + "/secrets/syncthing.sops.yaml")) {
        owner = config.users.main.name;
        mode = "0400";
      };

      # (Prometheus/Alertmanager firewall openings removed for this host)

      # Alertmanager removed; no SMTP credentials needed

      # PHP-FPM exporter removed on this host

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

      # Disable AppArmor PAM integration for sudo since the kernel lacks AppArmor hats
      security.pam.services = {
        sudo.enableAppArmor = lib.mkForce false;
        "sudo-rs".enableAppArmor = lib.mkForce false;
      };

      # Avoid forcing pkexec as setuid; Steam/SteamVR misbehaves when invoked with elevated EUID.
      # Use polkit rules if specific privileges are required instead of global setuid pkexec.

      # Provide nginx system user/group so PHP-FPM pool configs referencing
      # nginx for socket ownership won't fail even when nginx service is off.
      users = {
        users.nginx = {
          isSystemUser = true;
          group = "nginx";
        };
        # Allow Caddy to access php-fpm socket via shared group
        users.caddy.extraGroups = ["nginx"];
        groups.nginx = {};
      };
      # Allow main user to collaborate with Resilio data owned by rslsync
      users.users.${config.users.main.name}.extraGroups = lib.mkAfter ["rslsync"];

      # Games autoscale defaults for this host
      profiles.games = {
        autoscaleDefault = false;
        targetFps = 240;
        nativeBaseFps = 240;
      };

      # Limit auto-picked V-Cache CPU set size for game-run pinning
      environment.variables.GAME_PIN_AUTO_LIMIT = "8";

      # AutoFDO tooling disabled on this host (module kept)
      dev.gcc.autofdo.enable = false;

      systemd = {
        services = {
          # Энергосбережение по умолчанию для меньшего тепла/шума
          "power-profiles-default" = {
            description = "Set default power profile to power-saver";
            after = ["power-profiles-daemon.service"];
            wants = ["power-profiles-daemon.service"];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = "/run/current-system/sw/bin/powerprofilesctl set power-saver";
            };
            # Defer to post-boot to avoid interfering with activation and to follow repo policy
            wantedBy = ["post-boot.target"];
          };

          # Set Syncthing GUI user/password only after config is generated, before service starts
          "syncthing-set-gui-pass" = lib.mkIf (config.services.syncthing.enable or false) (let
            setPassScript = pkgs.writeShellScript "syncthing-set-gui-pass.sh" ''
              set -euo pipefail
              PASS_FILE="${config.sops.secrets."syncthing/gui-pass".path}"
              HOME_DIR="${config.services.syncthing.configDir}"
              if [ -r "$PASS_FILE" ]; then
                PASS="$(tr -d '\n' < "$PASS_FILE")"
                if [ -n "$PASS" ]; then
                  ${pkgs.syncthing}/bin/syncthing -home "$HOME_DIR" cli config gui user "${config.users.main.name}"
                  ${pkgs.syncthing}/bin/syncthing -home "$HOME_DIR" cli config gui password "$PASS"
                fi
              fi
            '';
          in {
            description = "Set Syncthing GUI credentials from SOPS secret";
            after = ["syncthing-init.service" "sops-nix.service"];
            requires = ["syncthing-init.service"];
            before = ["syncthing.service"];
            wantedBy = ["syncthing.service"];
            serviceConfig = {
              Type = "oneshot";
              User = config.users.main.name;
              Group = config.users.main.name;
              ExecStart = [setPassScript];
            };
          });

          "resilio-fs-setup" = lib.mkIf hasResilioSecret {
            description = "Prepare Resilio data directory /zero/sync";
            after = ["local-fs.target"];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = [resilioFsSetupScript];
            };
          };

          # Inject Resilio Web UI credentials from SOPS into generated config.json
          resilio = lib.mkIf hasResilioSecret {
            requires = lib.mkAfter ["resilio-fs-setup.service"];
            after = lib.mkAfter ["resilio-fs-setup.service"];
            serviceConfig.ExecStartPre = lib.mkAfter [resilioAuthScript];
          };

          # Periodic metric collection service + timer
          "bitcoind-textfile-metrics" = let
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
              headers=$(printf '%s\n' "$info" | ${pkgs.jq}/bin/jq -r '.headers // 0' 2>/dev/null || echo 0)
              chain=$(printf '%s\n' "$info" | ${pkgs.jq}/bin/jq -r '.chain // "unknown"' 2>/dev/null || echo unknown)

              # Determine best block time for staleness metric
              besthash=$($CLI getbestblockhash 2>/dev/null || echo)
              if [ -n "$besthash" ]; then
                block_time=$($CLI getblockheader "$besthash" 2>/dev/null | ${pkgs.jq}/bin/jq -r '.time // 0' 2>/dev/null || echo 0)
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
              peers=$($CLI getnetworkinfo 2>/dev/null | ${pkgs.jq}/bin/jq -r '.connections // 0' 2>/dev/null || echo 0)

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
          in {
            enable = false;
            description = "Export bitcoind minimal metrics to node_exporter textfile collector";
            serviceConfig = {
              Type = "oneshot";
              User = bitcoindUser;
              Group = bitcoindUser;
              ExecStart = metricsScript;
            };
            wants = ["bitcoind-${bitcoindInstance}.service"];
            after = ["bitcoind-${bitcoindInstance}.service"];
          };

          # Disable runtime logrotate check (build-time check remains). Avoids false negatives
          # when rotating files under non-standard paths or missing until first run.
          logrotate-checkconf.enable = false;
        };

        timers."bitcoind-textfile-metrics" = {
          enable = false;
          wantedBy = ["timers.target"];
          timerConfig = {
            OnBootSec = "2m";
            OnUnitActiveSec = "30s";
            AccuracySec = "5s";
            Unit = "bitcoind-textfile-metrics.service";
          };
        };
      };

      # Resilio Sync: Web UI auth via SOPS, data under /zero/sync
      sops.secrets."resilio/http-login" = lib.mkIf hasResilioSecret {
        sopsFile = inputs.self + "/secrets/resilio.sops.yaml";
        owner = "rslsync";
        mode = "0400";
      };
      sops.secrets."resilio/http-pass" = lib.mkIf hasResilioSecret {
        sopsFile = inputs.self + "/secrets/resilio.sops.yaml";
        owner = "rslsync";
        mode = "0400";
      };

      # Monitoring (role enables Netdata + sysstat + atop with light config)
      # Netdata UI: http://127.0.0.1:19999
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
            IPAddressAllow = ["127.0.0.0/8" "::1/128"];
          };
        };

        # Ensure plugins directory is clean on activation
        tmpfiles.rules = lib.mkAfter [
          "R /var/lib/grafana/plugins - - - - -"
          "d /var/lib/grafana/plugins 0750 grafana grafana - -"
        ];
      };

      # SOPS secret for Grafana admin password
      sops.secrets."grafana/admin_password" = let
        yaml = inputs.self + "/secrets/grafana-admin-password.sops.yaml";
        bin = inputs.self + "/secrets/grafana-admin-password.sops";
      in
        lib.mkIf (builtins.pathExists yaml || builtins.pathExists bin) {
          sopsFile =
            if builtins.pathExists yaml
            then yaml
            else bin;
          format = "binary"; # provide plain string to $__file provider
          # Ensure grafana can read the secret when referenced via $__file{}
          owner = "grafana";
          group = "grafana";
          mode = "0400";
          # Restart Grafana if the secret changes
          restartUnits = ["grafana.service"];
        };
    })
  ]
