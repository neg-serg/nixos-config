{
  lib,
  config,
  pkgs,
  ...
}: {
  # Primary user (single source of truth for name/ids)
  users.main = {
    name = "neg";
    uid = 1000;
    gid = 1000;
    description = "Neg";
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
      {
        domain = "grafana.telfir";
        answer = "192.168.2.240";
      }
    ];
    # Enable curated AdGuardHome filter lists
    adguardhome.filterLists = [
      # Core/general
      { name = "AdGuard DNS filter"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_1.txt"; enabled = true; }
      { name = "OISD full"; url = "https://big.oisd.nl/"; enabled = true; }
      { name = "AdAway"; url = "https://raw.githubusercontent.com/AdAway/adaway.github.io/master/hosts.txt"; enabled = false; }

      # Well-known hostlists (mostly covered by OISD, kept optional)
      { name = "Peter Lowe's Blocklist"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_3.txt"; enabled = false; }
      { name = "Dan Pollock's Hosts"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_4.txt"; enabled = false; }
      { name = "Steven Black's List"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_33.txt"; enabled = false; }

      # Security-focused
      { name = "Dandelion Sprout Anti‑Malware"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_12.txt"; enabled = true; }
      { name = "Phishing Army"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_18.txt"; enabled = true; }
      { name = "URLHaus Malicious URL"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_11.txt"; enabled = true; }
      { name = "Scam Blocklist (DurableNapkin)"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_10.txt"; enabled = true; }

      # Niche/optional
      { name = "NoCoin (Cryptomining)"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_8.txt"; enabled = false; }
      { name = "Smart‑TV Blocklist"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_7.txt"; enabled = false; }
      { name = "Game Console Adblock"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_6.txt"; enabled = false; }
      { name = "1Hosts Lite"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_24.txt"; enabled = false; }
      { name = "1Hosts Xtra"; url = "https://adguardteam.github.io/HostlistsRegistry/assets/filter_70.txt"; enabled = false; }

      # Regional (RU) — Adblock syntax lists; optional at DNS level
      { name = "AdGuard Russian filter"; url = "https://filters.adtidy.org/extension/ublock/filters/2.txt"; enabled = true; }
      { name = "RU AdList + EasyList"; url = "https://easylist-downloads.adblockplus.org/ruadlist+easylist.txt"; enabled = true; }
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

  # Disable Netdata on this host (keep other monitoring like sysstat)
  monitoring.netdata.enable = false;
  # Enable centralized logs (Loki + Promtail)
  monitoring.logs.enable = true;
  # Expose Loki on LAN (br0) and enable Grafana with Loki datasource
  monitoring.loki = {
    listenAddress = "0.0.0.0";
    openFirewall = true;
    firewallInterfaces = [ "br0" ];
  };
  monitoring.grafana = {
    enable = true;
    port = 3030;
    # Serve Grafana only via Caddy: bind to localhost and do not open the port
    listenAddress = "127.0.0.1";
    openFirewall = false;
    firewallInterfaces = [ "br0" ];
    # Admin via SOPS secret (if present)
    adminUser = "admin";
    # Point to the SOPS-managed file below
    adminPasswordFile = let
      yaml = ../../.. + "/secrets/grafana-admin-password.sops.yaml";
      bin = ../../.. + "/secrets/grafana-admin-password.sops";
    in if (builtins.pathExists yaml || builtins.pathExists bin)
       then config.sops.secrets."grafana/admin_password".path
       else null;
    # HTTPS via Caddy on grafana.telfir
    caddyProxy.enable = true;
    caddyProxy.domain = "grafana.telfir";
    caddyProxy.tlsInternal = true;
    caddyProxy.openFirewall = true;
    caddyProxy.firewallInterfaces = [ "br0" ];
  };

  # Disable RNNoise virtual mic for this host by default
  hardware.audio.rnnoise.enable = false;

  # Quiet fan profile: load nct6775 and autogenerate a conservative fancontrol config
  hardware.cooling = {
    enable = true;
    autoFancontrol = {
      enable = true;
      # Softer CPU curve for Zen 5 X3D: start later, cap lower
      minTemp = 40;  # °C to start ramping
      maxTemp = 70;  # °C for max speed
      # Keep default PWM/hysteresis/interval unless tuning proves stable
      # minPwm  = 70;
      # maxPwm  = 255;
      # hysteresis = 3;
      # interval  = 2;
    };
    gpuFancontrol = {
      enable = true;
      # Softer GPU curve: later start, lower full-speed point
      minTemp = 55;  # °C
      maxTemp = 80;  # °C
      # minPwm  = 70;
      # maxPwm  = 255;
      # hysteresis = 3;
    };
  };

  # Nextcloud via Caddy on LAN, served as "telfir"
  services = let
    devicesList = [
      {
        name = "telfir";
        id = "EZG57BT-TANWJ2R-QDVLV5X-4DKP7GU-HQENUT7-MA43GUU-AV3IN6P-7KKGZA3";
      }
      {
        name = "OPPO X7 Ultra";
        id = "JHDQEDC-YN67IMD-B7WFZTI-Y4CPKMY-MUPRBYK-OAFOMPC-IJVDVOV-AOBILAX";
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
        devices = ["telfir" "OPPO X7 Ultra"];
      }
      {
        name = "picture-upload";
        path = "/zero/syncthing/picture-upload";
        devices = ["OPPO X7 Ultra"];
      }
    ];
    folders = builtins.listToAttrs (
      map (f: {
        inherit (f) name;
        value = {inherit (f) path devices;};
      })
      foldersList
    );
  in {
    # AdGuard Home: enable Prometheus metrics endpoint at /control/metrics
    adguardhome.settings.prometheus.enabled = true;

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

    # Prometheus Node Exporter (OS metrics)
    prometheus.exporters.node = {
      enable = true;
      port = 9100;
      # Add extra collectors on top of defaults
      enabledCollectors = [ "systemd" "processes" "logind" "hwmon" "textfile" ];
      extraFlags = [
        "--collector.textfile.directory=/var/lib/node_exporter/textfile_collector"
      ];
      # Open firewall specifically for br0 interface via exporter module
      openFirewall = true;
      firewallFilter = "-i br0 -p tcp -m tcp --dport 9100";
    };

    # Prometheus Unbound Exporter (DNS resolver metrics)
    # Exposes metrics gathered via local unbound-control on 127.0.0.1:8953
    # Default exporter port is 9167; keep it localhost-only (no openFirewall)
    prometheus.exporters.unbound = {
      enable = true;
      port = 9167;
      openFirewall = false;
    };

    # Prometheus PHP-FPM Exporter (Nextcloud PHP pool)
    # Scrapes php-fpm status via unix socket of the 'nextcloud' pool
    prometheus.exporters."php-fpm" = {
      enable = true;
      # Default port is 9253; keep local-only
      openFirewall = false;
      extraFlags = [
        "--phpfpm.scrape-uri=unix:///run/phpfpm/nextcloud.sock;/status"
      ];
    };

    # Prometheus Blackbox Exporter (HTTP/DNS/ICMP probes)
    prometheus.exporters.blackbox = {
      enable = true;
      # Expose on default port and open only on br0
      port = 9115;
      openFirewall = true;
      firewallFilter = "-i br0 -p tcp -m tcp --dport 9115";
      # Modules: HTTP 2xx (strict + insecure TLS variant), TCP connect, ICMP ping (IPv4), DNS A lookup
      configFile = pkgs.writeText "blackbox.yml" ''
        modules:
          http_2xx:
            prober: http
            timeout: 5s
            http:
              method: GET
              valid_http_versions: ["HTTP/1.1", "HTTP/2"]

          http_2xx_insecure:
            prober: http
            timeout: 5s
            http:
              method: GET
              valid_http_versions: ["HTTP/1.1", "HTTP/2"]
              tls_config:
                insecure_skip_verify: true

          tcp_connect:
            prober: tcp
            timeout: 5s

          icmp:
            prober: icmp
            timeout: 5s
            icmp:
              preferred_ip_protocol: ip4

          dns:
            prober: dns
            timeout: 5s
            dns:
              transport_protocol: udp
              preferred_ip_protocol: ip4
              query_class: IN
              query_type: A
              query_name: example.com
      '';
    };

    # Example Prometheus scrape configs for Blackbox probes (Prometheus server can be enabled later)
    prometheus = {
      enable = true;
      scrapeConfigs = [
        # Prometheus self-scrape (UI/metrics)
        {
          job_name = "prometheus";
          static_configs = [ {
            targets = [
              "127.0.0.1:${toString config.services.prometheus.port}"
            ];
          } ];
        }
        # Unbound exporter metrics
        {
          job_name = "unbound";
          static_configs = [ {
            targets = [
              "127.0.0.1:${toString config.services.prometheus.exporters.unbound.port}"
            ];
          } ];
        }
        # AdGuard Home Prometheus metrics (local admin UI)
        {
          job_name = "adguardhome";
          metrics_path = "/control/metrics";
          static_configs = [ {
            targets = [ "127.0.0.1:3000" ];
          } ];
          # To protect metrics with API token later, set:
          # bearer_token_file = "/run/secrets/adguard_metrics_token";
          # and manage the secret via sops: sops.secrets."adguard/metrics-token".
        }
        # Node exporter metrics from this host
        {
          job_name = "node";
          static_configs = [ {
            targets = [
              "127.0.0.1:${toString config.services.prometheus.exporters.node.port}"
            ];
          } ];
        }
        # PHP-FPM exporter (Nextcloud pool)
        {
          job_name = "phpfpm";
          static_configs = [ {
            targets = [
              "127.0.0.1:${toString config.services.prometheus.exporters."php-fpm".port}"
            ];
          } ];
        }
        # HTTP checks: Nextcloud status and AdGuard UI (2xx expected)
        {
          job_name = "blackbox-http";
          metrics_path = "/probe";
          params.module = [ "http_2xx" ];
          static_configs = [ { targets = [
            "http://telfir/status.php"
            "http://127.0.0.1:3000/"
          ]; } ];
          relabel_configs = [
            { source_labels = [ "__address__" ]; target_label = "__param_target"; }
            { source_labels = [ "__param_target" ]; target_label = "instance"; }
            { target_label = "__address__"; replacement = "127.0.0.1:9115"; }
          ];
        }
        # HTTPS checks that may use self-signed certs on LAN
        {
          job_name = "blackbox-https-insecure";
          metrics_path = "/probe";
          params.module = [ "http_2xx_insecure" ];
          static_configs = [ { targets = [
            "https://telfir/status.php"
          ]; } ];
          relabel_configs = [
            { source_labels = [ "__address__" ]; target_label = "__param_target"; }
            { source_labels = [ "__param_target" ]; target_label = "instance"; }
            { target_label = "__address__"; replacement = "127.0.0.1:9115"; }
          ];
        }
        # ICMP reachability to public resolvers (basic external connectivity)
        {
          job_name = "blackbox-icmp";
          metrics_path = "/probe";
          params.module = [ "icmp" ];
          static_configs = [ { targets = [
            "1.1.1.1"
            "8.8.8.8"
          ]; } ];
          relabel_configs = [
            { source_labels = [ "__address__" ]; target_label = "__param_target"; }
            { source_labels = [ "__param_target" ]; target_label = "instance"; }
            { target_label = "__address__"; replacement = "127.0.0.1:9115"; }
          ];
        }
        # DNS A lookups via blackbox (targets are DNS servers; module queries example.com)
        {
          job_name = "blackbox-dns";
          metrics_path = "/probe";
          params.module = [ "dns" ];
          static_configs = [ { targets = [
            "127.0.0.1:53"
            "1.1.1.1:53"
          ]; } ];
          relabel_configs = [
            { source_labels = [ "__address__" ]; target_label = "__param_target"; }
            { source_labels = [ "__param_target" ]; target_label = "instance"; }
            { target_label = "__address__"; replacement = "127.0.0.1:9115"; }
          ];
        }
      ];
      alertmanagers = [
        {
          static_configs = [ { targets = [ "127.0.0.1:9093" ]; } ];
        }
      ];
      rules = [ ''
groups:
- name: base.alerts
  rules:
  - alert: InstanceDown
    expr: up == 0
    for: 2m
    labels:
      severity: critical
    annotations:
      summary: "Instance {{ $labels.instance }} down"
      description: "Job {{ $labels.job }} on {{ $labels.instance }} is down for 2m."

  - alert: HighCPULoad
    expr: avg by (instance) (rate(node_cpu_seconds_total{mode!="idle"}[5m])) > 0.9
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High CPU load on {{ $labels.instance }}"
      description: ">90% average CPU usage in 5m."

  - alert: HighMemoryUsage
    expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.9
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "High memory usage on {{ $labels.instance }}"
      description: ">90% memory used for 10m."

  - alert: DiskSpaceLow
    expr: (node_filesystem_avail_bytes{fstype!~"tmpfs|ramfs|overlay",mountpoint!~"/(proc|sys|run)($|/)",device!~"^ram|^loop"} / node_filesystem_size_bytes{fstype!~"tmpfs|ramfs|overlay",mountpoint!~"/(proc|sys|run)($|/)",device!~"^ram|^loop"}) < 0.10
    for: 10m
    labels:
      severity: warning
    annotations:
      summary: "Low disk space on {{ $labels.instance }} {{ $labels.mountpoint }}"
      description: "Free space <10% for 10m."

  - alert: BlackboxHttpProbeFail
    expr: probe_success{job=~"blackbox-http|blackbox-https-insecure"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "HTTP probe failing: {{ $labels.instance }}"
      description: "Blackbox HTTP probe returns failure."

  - alert: BlackboxIcmpProbeFail
    expr: probe_success{job="blackbox-icmp"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "ICMP probe failing: {{ $labels.instance }}"
      description: "Blackbox ICMP probe returns failure."

  - alert: BlackboxDnsProbeFail
    expr: probe_success{job="blackbox-dns"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "DNS probe failing: {{ $labels.instance }}"
      description: "Blackbox DNS probe returns failure."

  - alert: HighHttpLatency
    expr: probe_duration_seconds{job=~"blackbox-http|blackbox-https-insecure"} > 2
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High HTTP latency: {{ $labels.instance }}"
      description: ">2s average probe duration for 5m."

  - alert: HighDnsLatency
    expr: probe_duration_seconds{job="blackbox-dns"} > 2
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "High DNS latency: {{ $labels.instance }}"
      description: ">2s average DNS probe duration for 5m."
'' ];
      # Expose Prometheus UI only on br0 (module has no openFirewall option)
      # so we open firewall per-interface next to the service for clarity.
      # Port follows services.prometheus.port (default 9090).
      # If you change the port, update this list accordingly.
      # Note: this is interface-scoped, not global.
      #
      # If you prefer nftables rules string, we can switch to extraRules.
    };

    # (firewall rule for Prometheus UI is defined at top-level below)

    # Alertmanager service (exposed via firewall on br0 only)
    prometheus.alertmanager = {
      enable = true;
      configuration = {
        # SMTP via Gmail (use app password via environment file below)
        global = {
          smtp_smarthost = "smtp.gmail.com:587";
          smtp_from = "serg.zorg@gmail.com";
          smtp_auth_username = "$ALERT_SMTP_USER";
          smtp_auth_password = "$ALERT_SMTP_PASS";
          smtp_require_tls = true;
        };
        route = {
          receiver = "email-serg";
          group_by = [ "alertname" "job" "instance" ];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "3h";
        };
        receivers = [
          {
            name = "email-serg";
            email_configs = [
              {
                to = "serg.zorg@gmail.com";
                send_resolved = true;
              }
            ];
          }
          { name = "default"; }
        ];
        inhibit_rules = [
          {
            source_matchers = [ "severity = critical" ];
            target_matchers = [ "severity = warning" ];
            equal = [ "alertname" "instance" "job" ];
          }
        ];
      };
      # Load credentials from SOPS-managed dotenv if present
      environmentFile = lib.mkIf (builtins.pathExists (../../.. + "/secrets/alertmanager.env.sops")) (
        config.sops.secrets."alertmanager/env".path
      );
    };

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

    # Add Prometheus datasource to Grafana so Unbound/Nextcloud metrics are browsable out-of-the-box
    grafana.provision.datasources.settings.datasources = lib.mkAfter [
      {
        uid = "prometheus";
        name = "Prometheus";
        type = "prometheus";
        access = "proxy";
        url = "http://127.0.0.1:${toString config.services.prometheus.port}";
        isDefault = false;
      }
    ];

    # Provision local dashboards (Unbound, Nextcloud)
    grafana.provision.dashboards.settings.providers = lib.mkAfter [
      {
        name = "local-json";
        orgId = 1;
        type = "file";
        disableDeletion = false;
        editable = true;
        options.path = ../../dashboards;
      }
    ];

    # Bitcoind instance is now managed by modules/servers/bitcoind
  };

  # Provide GUI password to Syncthing from SOPS secret and set it at service start
  # - Secret file: secrets/syncthing.sops.yaml (key: syncthing/gui-pass)
  # - Make it readable by the Syncthing user and apply via ExecStartPre
  sops.secrets."syncthing/gui-pass" = lib.mkIf (builtins.pathExists (../../.. + "/secrets/syncthing.sops.yaml")) {
    owner = config.users.main.name;
    mode = "0400";
  };

  # Set Syncthing GUI user/password only after config is generated, before service starts
  systemd.services."syncthing-set-gui-pass" = lib.mkIf (config.services.syncthing.enable or false) (let
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
    after = [ "syncthing-init.service" "sops-nix.service" ];
    requires = [ "syncthing-init.service" ];
    before = [ "syncthing.service" ];
    wantedBy = [ "syncthing.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = config.users.main.name;
      Group = config.users.main.name;
      ExecStart = [ setPassScript ];
    };
  });

  # Firewall: allow Prometheus UI and Alertmanager on br0 only
  networking.firewall.interfaces.br0.allowedTCPPorts = [ 9090 9093 ];

  # Disable preinstall/auto-update feature toggle explicitly via env (Grafana 10/11/12)
  systemd.services.grafana.environment = {
    GF_FEATURE_TOGGLES_DISABLE = "preinstallAutoUpdate";
  };

  # Restrict Grafana network egress to loopback only.
  # Caddy proxies from LAN to 127.0.0.1, and datasources (Loki/Prometheus) are local.
  # This blocks accidental outbound calls (updates, gravatar, external plugins, etc.).
  systemd.services.grafana.serviceConfig = {
    IPAddressDeny = "any";
    IPAddressAllow = [ "127.0.0.0/8" "::1/128" ];
  };

  # Ensure plugins directory is clean on activation and ensure node_exporter textfile dir
  systemd.tmpfiles.rules = lib.mkAfter (
    [
      "R /var/lib/grafana/plugins - - - - -"
      "d /var/lib/grafana/plugins 0750 grafana grafana - -"
    ]
    ++ (let
          bitcoindEnabled = config.servicesProfiles.bitcoind.enable or false;
          bitcoindInstance = config.servicesProfiles.bitcoind.instance or "main";
          bitcoindUser = "bitcoind-${bitcoindInstance}";
          textfileDir = "/var/lib/node_exporter/textfile_collector";
        in lib.optional bitcoindEnabled "d ${textfileDir} 0755 ${bitcoindUser} ${bitcoindUser} -")
  );

  # SOPS secret for Alertmanager SMTP credentials (dotenv with ALERT_SMTP_USER/PASS)
  sops.secrets."alertmanager/env" = lib.mkIf (builtins.pathExists (../../.. + "/secrets/alertmanager.env.sops")) {
    sopsFile = ../../../secrets/alertmanager.env.sops;
    format = "binary"; # do not parse; pass through as plaintext env file
  };


  # SOPS secret for Grafana admin password
  sops.secrets."grafana/admin_password" = let
    yaml = ../../../secrets/grafana-admin-password.sops.yaml;
    bin = ../../../secrets/grafana-admin-password.sops;
  in lib.mkIf (builtins.pathExists yaml || builtins.pathExists bin) {
    sopsFile = if builtins.pathExists yaml then yaml else bin;
    format = "binary"; # provide plain string to $__file provider
    # Ensure grafana can read the secret when referenced via $__file{}
    owner = "grafana";
    group = "grafana";
    mode = "0400";
    # Restart Grafana if the secret changes
    restartUnits = [ "grafana.service" ];
  };

  # Start php-fpm exporter after the Nextcloud PHP-FPM pool is up to avoid startup failures
  systemd.services."prometheus-php-fpm-exporter" = {
    after = lib.mkAfter [ "phpfpm-nextcloud.service" "phpfpm.service" "nextcloud-setup.service" ];
    wants = lib.mkAfter [ "phpfpm-nextcloud.service" ];
    serviceConfig = {
      # Run under the Prometheus user instead of a dynamic sandbox user
      DynamicUser = lib.mkForce false;
      User = lib.mkForce "prometheus";
      Group = lib.mkForce "prometheus";
      # Ensure access to the php-fpm socket group
      SupplementaryGroups = [ "nginx" ];
      # Allow connecting to the php-fpm unix socket
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # Bitcoind minimal metrics → node_exporter textfile collector
  # Exposes:
  #   bitcoin_block_height{instance="main",chain="<chain>"} <n>
  #   bitcoin_headers{instance="main",chain="<chain>"} <n>
  #   bitcoin_time_since_last_block_seconds{instance} <seconds>
  #   bitcoin_peers_connected{instance} <n>
  # Directory for textfile collector is ensured above via tmpfiles rules

  # Periodic metric collection service + timer
  systemd.services."bitcoind-textfile-metrics" = let
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
    wants = [ "bitcoind-${bitcoindInstance}.service" ];
    after = [ "bitcoind-${bitcoindInstance}.service" ];
  };
  systemd.timers."bitcoind-textfile-metrics" = {
    enable = false;
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2m";
      OnUnitActiveSec = "30s";
      AccuracySec = "5s";
      Unit = "bitcoind-textfile-metrics.service";
    };
  };



  # Firewall port for bitcoind is opened by the bitcoind server module

  # Disable runtime logrotate check (build-time check remains). Avoids false negatives
  # when rotating files under non-standard paths or missing until first run.
  systemd.services.logrotate-checkconf.enable = false;

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
    # Allow Caddy and Prometheus exporter to access php-fpm socket via shared group
    users.caddy.extraGroups = [ "nginx" ];
    users.prometheus.extraGroups = [ "nginx" ];
    groups.nginx = {};
  };

  # Games autoscale defaults for this host
  profiles.games = {
    autoscaleDefault = false;
    targetFps = 240;
    nativeBaseFps = 240;
  };

  # AutoFDO tooling disabled on this host (module kept)
  dev.gcc.autofdo.enable = false;

  # Monitoring (role enables Netdata + sysstat + atop with light config)
  # Netdata UI: http://127.0.0.1:19999
}
