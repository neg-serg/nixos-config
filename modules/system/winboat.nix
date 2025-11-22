{
  lib,
  pkgs,
  config,
  ...
}: let
  winboatCfg = config.features.apps.winboat or {};
  enabled = winboatCfg.enable or false;
  mainUser = config.users.main.name or "neg";
in {
  config = lib.mkIf enabled {
    # Enable Docker engine when WinBoat integration is on and disable Podman
    # Docker compatibility so sockets do not conflict.
    virtualisation = {
      docker.enable = true;
      podman = {
        dockerCompat = lib.mkForce false;
        dockerSocket.enable = lib.mkForce false;
      };
    };

    # WinBoat runtime dependencies:
    # - docker-compose v2 (docker-compose command)
    # - FreeRDP client (xfreerdp) for Windows app sessions
    environment.systemPackages = lib.mkAfter [
      pkgs.docker-compose
      pkgs.freerdp
    ];

    # Ensure the primary user can talk to the Docker daemon.
    users.users.${mainUser}.extraGroups = lib.mkAfter ["docker"];
  };
}
