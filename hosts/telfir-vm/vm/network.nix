_: {
  # Align with qemu-vm module: disable timesyncd to avoid conflicts
  services.timesyncd.enable = false;

  # Basic DHCP for any interface; no bridges in VM
  networking.firewall.enable = false;
  networking.hostName = "telfir-vm";
  systemd.network.networks."99-vm-default" = {
    matchConfig.Name = "*";
    networkConfig.DHCP = "ipv4";
  };
}
