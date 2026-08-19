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

  # Monitor ALL network interfaces: with an empty Interface the daemon
  # populates the database with every suitable interface found at startup
  # (pseudo interfaces lo/sit0 are always excluded by vnstatd), and
  # AlwaysAddNewInterfaces picks up new interfaces appearing at runtime
  # (VPN tunnels, docker bridges, ...). Keeping Interface empty also lets
  # the vnstat CLI auto-select the busiest interface (a "*" wildcard here
  # would break bare `vnstat` invocations).
  # The config is passed explicitly with --config because the daemon
  # otherwise reads the uneditable config baked into the vnstat store path.
  environment.etc."vnstat.conf".text = ''
    AlwaysAddNewInterfaces 1
  '';

  systemd.services.vnstat.serviceConfig.ExecStart =
    lib.mkForce "${config.services.vnstat.package}/bin/vnstatd -n --config /etc/vnstat.conf";
}
