{lib, ...}: {
  # Disable heavy services in the VM to speed up eval/builds
  profiles.services = {
    adguardhome.enable = false;
    unbound.enable = false;
    jellyfin.enable = false;
  };

  # Lighten system for VM builds (docs off)
  documentation.enable = lib.mkDefault false;
}
