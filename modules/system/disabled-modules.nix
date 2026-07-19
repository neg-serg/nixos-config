{ ... }: {
  disabledModules = [
    # Web servers — not used on odin (no web serving from this machine)
    "services/web-servers/nginx.nix"
    # "services/web-servers/apache-httpd/default.nix"  # referenced by zabbix web frontend
    # "services/web-servers/caddy/default.nix"  # referenced by wordpress.nix
    # "services/web-servers/traefik.nix"  # referenced by pangolin.nix
    "services/web-servers/haproxy.nix"

    # Databases — not used on odin
    # "services/databases/postgresql.nix"  # referenced by too many modules (taler, peertube, plausible, etc.)
    # "services/databases/mysql.nix"  # referenced by writefreely.nix
    "services/databases/mariadb.nix"
    # "services/databases/redis.nix"  # referenced by send.nix
    # "services/databases/mongodb.nix"  # referenced by your_spotify.nix
    "services/databases/influxdb.nix"
    # "services/databases/clickhouse.nix"  # referenced by plausible.nix
    "services/databases/cockroachdb.nix"
    "services/databases/cassandra.nix"
    "services/databases/neo4j.nix"

    # CI/CD — not used (jenkins/default.nix kept — job-builder submodule depends on it; same for gitlab-runner)
    # "services/continuous-integration/jenkins/default.nix"  # job-builder.nix references it
    # "services/continuous-integration/gitlab-runner.nix"     # referenced by web-apps

    # Mail servers — not used
    # "services/mail/postfix.nix"  # referenced by peertube.nix
    # "services/mail/dovecot.nix"  # referenced by parsedmarc.nix
    "services/mail/rspamd.nix"
    "services/mail/opensmtpd.nix"

    # Printing — no printer on odin
    # "services/printing/cupsd.nix"  # referenced by vmware-host.nix
    "services/printing/ipp-usb.nix"

    # VoIP/telephony
    "services/networking/asterisk.nix"

    # K8s / container orchestration (kubernetes disabled; nomad has cross-refs with other modules)

    # Game servers
    "services/games/valheim/default.nix"
    "services/games/minecraft-server.nix"

    # Monitoring we don't use
    "services/monitoring/prometheus/default.nix"
    "services/monitoring/thanos.nix"
    "services/monitoring/telegraf.nix"
    "services/monitoring/zabbix-agent.nix"

    # Misc servers we don't use
    "services/misc/gitlab.nix"
    "services/misc/gitea.nix"
    "services/misc/plex.nix"
    "services/misc/emby.nix"
    "services/misc/matrix-synapse.nix"
    "services/misc/paperless.nix"
    "services/misc/grocy.nix"

    # Desktop managers — plasma6 disabled because SDDM module was removed from nixpkgs-unstable
    "services/desktop-managers/plasma6.nix"

    # Display managers — odin uses greetd with autologin
    "services/display-managers/gdm.nix"
    "services/display-managers/ly.nix"
    "services/display-managers/lemurs.nix"
    "services/display-managers/cosmic-greeter.nix"
    "services/display-managers/dms-greeter.nix"
    "services/display-managers/plasma-login-manager.nix"

    # Auto-detection (facter) — disabled because nixpkgs-slim removed hyperv-guest.nix
    # which facter's virtualisation module references. Odin is bare metal; no auto-detection needed.
    "hardware/facter"
  ];
}
