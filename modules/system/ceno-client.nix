{ lib, config, ... }:
{
  # Ceno/Ouinet P2P client (https://censorship.no/) — runs the official
  # equalitie/ceno-client container (ouinet client) via podman with host
  # networking: HTTP proxy on 127.0.0.1:8077, admin frontend on
  # 127.0.0.1:8078, P2P on UDP 28729. Node state persists in the named
  # volume "ceno" (/var/opt/ouinet in the container).
  config = lib.mkIf (config.lib.neg.enabled "net.ceno") {
    assertions = [
      {
        assertion = config.lib.neg.enabled "virt.docker";
        message = "features.net.ceno.enable requires features.virt.docker.enable = true (podman/docker-compat stack)";
      }
    ];

    virtualisation.oci-containers.containers.ceno-client = {
      image = "equalitie/ceno-client:v1.6.10"; # Ouinet client (Ceno network node)
      autoStart = true;
      volumes = [ "ceno:/var/opt/ouinet" ]; # persistent node state (named volume)
      extraOptions = [ "--network=host" ]; # P2P + local proxy/frontend on host net
      # BEP5 bridge announcements need a reachable public address, and this
      # host has no global IPv6: every attempt fails with "Network is
      # unreachable" (~1.1k WARN/day). v1.6.10 has no per-message filter and
      # the global log-level would hide real warnings too, so disable the
      # announcer itself (documented client.conf key); the DHT entry cannot be
      # reached from here anyway. Re-enable if the host gets a public address.
      cmd = [
        "client"
        "--disable-bridge-announcement"
      ];
      # ouinet-rs logs every metrics tick at DEBUG into the journal (~1.2k lines
      # per boot, all of it its own bookkeeping). INFO keeps the useful lines
      # (UPnP mapping, fetcher state).
      environment = {
        RUST_LOG = "info";
      };
    };

    # Inbound UDP for P2P seeding/bridging; TCP proxy (8077) and admin
    # frontend (8078) stay reachable on localhost only.
    networking.firewall.allowedUDPPorts = [ 28729 ];
  };
}
