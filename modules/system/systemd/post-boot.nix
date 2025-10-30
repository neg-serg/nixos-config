{
  lib,
  config,
  ...
}: let
  mkPostBoot = _:
    lib.mkIf true {
      # Defer the unit under the post-boot target without introducing
      # ordering cycles. Do not add After=graphical.target here because
      # these units are indirectly wanted by graphical.target via the
      # post-boot target itself.
      wantedBy = lib.mkForce ["post-boot.target"];
    };
in {
  # Define a target for non-critical background services that can start after desktop is up.
  systemd.targets.post-boot = {
    description = "Post-boot background services";
    # Have graphical.target pull this target in; do NOT set After=graphical.target here,
    # otherwise graphical.target → post-boot.target and post-boot.target → After=graphical.target
    # creates an ordering cycle. Individual services added to post-boot are ordered After=graphical.target.
    wantedBy = ["graphical.target"]; # reached along with graphical session
  };

  # Defer heavier services to post-boot when enabled.
  systemd.services = {
    # Network: move iwd out of critical path (starts after graphical)
    iwd = lib.mkIf (config.networking.wireless.iwd.enable or false) (mkPostBoot "iwd");

    # Libvirt stack after graphical
    libvirtd = lib.mkIf (config.virtualisation.libvirtd.enable or false) (mkPostBoot "libvirtd");
    "libvirt-guests" = lib.mkIf (config.virtualisation.libvirtd.enable or false) (mkPostBoot "libvirt-guests");

    # Syncthing init helper (created by upstream module)
    "syncthing-init" = lib.mkIf (config.services.syncthing.enable or false) (mkPostBoot "syncthing-init");

    # Ollama model server
    ollama = lib.mkIf (config.services.ollama.enable or false) (mkPostBoot "ollama");

    # Nextcloud stack pieces
    mysql = lib.mkIf (config.services.nextcloud.enable or false) (mkPostBoot "mysql");
    "redis-nextcloud" = lib.mkIf (config.services.nextcloud.enable or false) (mkPostBoot "redis-nextcloud");
    "phpfpm-nextcloud" = lib.mkIf (config.services.nextcloud.enable or false) (mkPostBoot "phpfpm-nextcloud");
    "nextcloud-setup" = lib.mkIf (config.services.nextcloud.enable or false) (mkPostBoot "nextcloud-setup");

    # Proxies (if enabled)
    caddy = lib.mkIf (config.services.caddy.enable or false) (mkPostBoot "caddy");
    nginx = lib.mkIf (config.services.nginx.enable or false) (mkPostBoot "nginx");

    # Local DNS stack
    unbound = lib.mkIf (config.services.unbound.enable or false) (mkPostBoot "unbound");
    adguardhome = lib.mkIf (config.services.adguardhome.enable or false) (
      (mkPostBoot "adguardhome") // {
        # Ensure DNS chain is ready before AdGuard binds on 53
        after = lib.optional (config.services.unbound.enable or false) "unbound.service"
          ++ lib.optional (config.services.resolved.enable or false) "systemd-resolved.service";
        wants = lib.optional (config.services.unbound.enable or false) "unbound.service";
      }
    );

    # Monitoring
    netdata = lib.mkIf (config.services.netdata.enable or false) (mkPostBoot "netdata");
  };
}
