##
# Module: servers/qdrant
# Purpose: Qdrant is a vector database for semantic search and RAG via Podman.
# Key options: profiles.services.qdrant (enable, dataDir, httpPort, grpcPort).
# Dependencies: virtualisation.oci-containers (backend = podman).
{
  lib,
  config,
  ...
}:
let
  cfg = config.profiles.services.qdrant;
  inherit (lib)
    mkEnableOption
    mkOption
    types
    mkIf
    ;
in
{
  options.profiles.services.qdrant = {
    enable = mkEnableOption "Qdrant vector database container";

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/qdrant";
      description = "Directory for Qdrant storage and data";
    };

    httpPort = mkOption {
      type = types.port;
      default = 6333;
      description = "Local port for Qdrant HTTP API";
    };

    grpcPort = mkOption {
      type = types.port;
      default = 6334;
      description = "Local port for Qdrant gRPC API";
    };

    timezone = mkOption {
      type = types.str;
      default = config.time.timeZone;
      description = "Container timezone";
    };
  };

  config = mkIf cfg.enable {
    # Ensure data directory exists
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
    ];

    virtualisation.oci-containers.containers.qdrant = {
      # Disabled by default - start manually with: sudo podman start qdrant
      autoStart = false;
      image = "qdrant/qdrant";
      environment = {
        TZ = cfg.timezone;
      };
      ports = [
        "${toString cfg.httpPort}:6333"
        "${toString cfg.grpcPort}:6334"
      ];
      volumes = [
        "${cfg.dataDir}:/qdrant/storage"
      ];
      extraOptions = [ "--name=qdrant" ];
    };

    # Open firewall ports
    networking.firewall.allowedTCPPorts = [
      cfg.httpPort
      cfg.grpcPort
    ];
  };
}
