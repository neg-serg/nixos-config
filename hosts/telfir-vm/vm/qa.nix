{lib, ...}: {
  # Disable heavy services in the VM to speed up eval/builds
  profiles.services = {
    nextcloud.enable = false;
    adguardhome.enable = false;
    syncthing.enable = false;
    unbound.enable = false;
    jellyfin.enable = false;
    navidrome.enable = false;
    wakapi.enable = false;
  };

  # Lighten system for VM builds (docs off)
  documentation.enable = lib.mkDefault false;
}
