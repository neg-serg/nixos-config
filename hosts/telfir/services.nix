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
    bitcoind = {
      enable = true;
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
    listenAddress = "0.0.0.0";
    openFirewall = true;
    firewallInterfaces = [ "br0" ];
    # Admin via SOPS secret (if present)
    adminUser = "admin";
    # Point to the SOPS-managed file below
    adminPasswordFile = let
      yaml = ../../.. + "/secrets/grafana-admin-password.sops.yaml";
      bin = ../../.. + "/secrets/grafana-admin-password.sops";
    in lib.mkIf (builtins.pathExists yaml || builtins.pathExists bin) (
      config.sops.secrets."grafana/admin_password".path
    );
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
    autoFancontrol.enable = true;
    gpuFancontrol.enable = true;
    # Optional tuning (defaults are quiet and safe); uncomment to adjust
    # autoFancontrol.minTemp = 35;  # start ramping at 35°C
    # autoFancontrol.maxTemp = 75;  # full speed by 75°C
    # autoFancontrol.minPwm  = 70;  # ~27% duty to avoid stall
    # autoFancontrol.maxPwm  = 255; # 100%
    # autoFancontrol.hysteresis = 3;
    # autoFancontrol.interval  = 2; # seconds
    # GPU curve (quiet): starts gentle at 50°C, full by 85°C
    # gpuFancontrol.minTemp = 50;
    # gpuFancontrol.maxTemp = 85;
    # gpuFancontrol.minPwm  = 70;
    # gpuFancontrol.maxPwm  = 255;
    # gpuFancontrol.hysteresis = 3;
  };

  # Nextcloud via Caddy on LAN, served as "telfir"
  services = let
    devicesList = [
      {
        name = "telfir";
        id = "EZG57BT-TANWJ2R-QDVLV5X-4DKP7GU-HQENUT7-MA43GUU-AV3IN6P-7KKGZA3";
      }
      {
        name = "Pixel 7 Pro";
        id = "OWGOTRT-Q4LV2MR-QLVIFZH-LPWZ4DP-TANYCAM-SXC2W2A-BL4VSHS-KWXLVAB";
      }
      {
        name = "DX180";
        id = "NKSYBIH-G5BV2FK-ZHHL27B-MWZT3OJ-DPTF7TH-O6HE5CM-3CARZ5K-6CIUSQI";
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
        devices = ["telfir" "Pixel 7 Pro" "DX180" "OPPO X7 Ultra"];
      }
      {
        name = "picture-upload";
        path = "/zero/syncthing/picture-upload";
        devices = ["Pixel 7 Pro" "DX180"];
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

    smartd = {
      enable = true;
      # Full monitoring, enable automatic offline tests, persist attributes,
      # temperature thresholds for NVMe, and schedule self-tests:
      # - Short test daily at 02:00; long test weekly on Sunday at 04:00
      defaults.monitored = "-a -o on -S on -W 5,70,80 -s (S/../.././02|L/../../7/04)";
      # Polling interval for smartd (seconds). Default is ~30 minutes; set to 1 hour.
      extraOptions = [ "--interval=3600" ];
    };

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
      enabledCollectors = [ "systemd" "processes" "logind" "hwmon" ];
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
      };
    };
    # Bitcoind instance is now managed by modules/servers/bitcoind
  };

  # Firewall: allow Prometheus UI and Alertmanager on br0 only
  networking.firewall.interfaces.br0.allowedTCPPorts = [ 9090 9093 ];

  # SOPS secret for Alertmanager SMTP credentials (dotenv with ALERT_SMTP_USER/PASS)
  sops.secrets."alertmanager/env" = lib.mkIf (builtins.pathExists (../../.. + "/secrets/alertmanager.env.sops")) {
    sopsFile = ../../../secrets/alertmanager.env.sops;
    format = "binary"; # do not parse; pass through as plaintext env file
  };

  # Add Prometheus datasource to Grafana so Unbound metrics are browsable out-of-the-box
  services.grafana.provision.datasources.settings.datasources = [
    {
      name = "Prometheus";
      type = "prometheus";
      access = "proxy";
      url = "http://127.0.0.1:${toString config.services.prometheus.port}";
      isDefault = false;
    }
  ];

  # SOPS secret for Grafana admin password
  sops.secrets."grafana/admin_password" = let
    yaml = ../../../secrets/grafana-admin-password.sops.yaml;
    bin = ../../../secrets/grafana-admin-password.sops;
  in lib.mkIf (builtins.pathExists yaml || builtins.pathExists bin) {
    sopsFile = if builtins.pathExists yaml then yaml else bin;
    format = "binary"; # provide plain string to $__file provider
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
