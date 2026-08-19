##
# Module: monitoring/vnstat
# Purpose: Enable vnstatd with default configuration.
# Key options: none.
# Dependencies: pkgs.vnstat (CLI/daemon).
{
  config,
  lib,
  ...
}:
{
  services = {
    vnstat.enable = true;
  };

  # Monitor ALL network interfaces instead of only the first suitable one:
  # - Interface "*" adds every suitable interface found at daemon startup
  #   (pseudo interfaces lo/sit0 are always excluded by vnstatd);
  # - AlwaysAddNewInterfaces picks up new interfaces appearing at runtime
  #   (VPN tunnels, docker bridges, ...).
  # The config is passed explicitly with --config because the daemon
  # otherwise reads the uneditable config baked into the vnstat store path.
  environment.etc."vnstat.conf".text = ''
    Interface "*"
    AlwaysAddNewInterfaces 1
  '';

  systemd.services.vnstat.serviceConfig.ExecStart =
    lib.mkForce "${config.services.vnstat.package}/bin/vnstatd -n --config /etc/vnstat.conf";
}
