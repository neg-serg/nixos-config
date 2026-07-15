{ pkgs, ... }:
{

  imports = [
    ./hardware.nix
    ./networking.nix
    ./services.nix
    ./virtualisation/lxc.nix
    # nixpkgs-slim compat: provides stub for services.mail.sendmailSetuidWrapper
    # (removed from slim nixpkgs together with the services/mail/ dir, but referenced
    #  by the zfs module's default for services.zfs.zed.enableMail).
    ./compat/mail-stub.nix
  ];

  # Disable unused nixpkgs service modules to reduce evaluation time and closure size.
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

    # Display managers — odin uses greetd with autologin
    "services/display-managers/gdm.nix"
    "services/display-managers/sddm.nix"
    "services/display-managers/ly.nix"
    "services/display-managers/lemurs.nix"
    "services/display-managers/cosmic-greeter.nix"
    "services/display-managers/dms-greeter.nix"
    "services/display-managers/plasma-login-manager.nix"

    # GNOME desktop submodules — odin uses Hyprland, not GNOME
    # (gnome-keyring.nix and gcr-ssh-agent.nix kept — used for D-Bus Secret Service)
    "services/desktops/gnome/at-spi2-core.nix"
    "services/desktops/gnome/evolution-data-server.nix"
    "services/desktops/gnome/glib-networking.nix"
    "services/desktops/gnome/gnome-browser-connector.nix"
    "services/desktops/gnome/gnome-initial-setup.nix"
    "services/desktops/gnome/gnome-online-accounts.nix"
    "services/desktops/gnome/gnome-online-miners.nix"
    "services/desktops/gnome/gnome-remote-desktop.nix"
    "services/desktops/gnome/gnome-settings-daemon.nix"
    "services/desktops/gnome/gnome-software.nix"
    "services/desktops/gnome/gnome-user-share.nix"
    "services/desktops/gnome/localsearch.nix"
    "services/desktops/gnome/rygel.nix"
    "services/desktops/gnome/sushi.nix"
    "services/desktops/gnome/tinysparql.nix"

    # Auto-detection (facter) — disabled because nixpkgs-slim removed hyperv-guest.nix
    # which facter's virtualisation module references. Odin is bare metal; no auto-detection needed.
    "hardware/facter"
  ];

  system.preserveFlake = false;
  # Composable profiles: order matters, last wins on conflicts
  features.profiles = [
    "desktop"
    "dev"
    "gaming"
  ];

  # Console font (visible before plymouth and on tty1-6)
  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-124n.psf.gz";
  };

  # Host-specific overrides (above profile defaults)
  # Obsidian installed via Flatpak (to avoid Electron in Nix closure)
  features.web.vivaldi.enable = true;
  features.web.default = "vivaldi";
  features.mail.vdirsyncer.enable = false;
  features.hardware.bluetooth.enable = false;
  features.net.proxy.enable = true;
  features.net.lan-proxy.enable = true;
  features.net.transparent-proxy.enable = true;
  features.dev.haskell.enable = false; # Disable Haskell toolchain (saves ~1GB)
  features.virt.libvirtd.enable = false; # Disable KVM/QEMU (not needed on this host)
  features.apps.guiAppsFull.enable = false; # Disable heavy GUI apps (GIMP, OBS); gaming profile enables it by default
  features.gui.vicinae.enable = true; # Vicinae Wayland app runner + window switcher
  features.gui.vicinae.manageConfig = true; # Nix-managed vicinae theme/settings (neg.nvim-style)
  features.gui.hdr.enable = false; # Disable HDR (DXVK_HDR) — Hyprland not configured for it, causes washed-out fullscreen
  features.dev.cpp.enable = true; # Enable C++ toolchain (ccache, gcc, cmake)
  # Override default networkUnits: odin uses systemd-networkd, not NetworkManager
  features.system.logTtys.networkUnits = [
    "systemd-networkd.service" # Primary network configuration
    "sshd.service" # SSH daemon
    "tailscaled.service" # Tailscale VPN
    "nftables.service" # Firewall
  ];
  boot.plymouth.enable = false; # Plymouth removed — adds boot delay, splash not needed on this host
}
