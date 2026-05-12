##
# Module: monitoring/vnstat
# Purpose: Enable vnstatd with default configuration.
# Key options: none.
# Dependencies: pkgs.vnstat (CLI/daemon).
_: {
  services = {
    vnstat.enable = true;
  };
  # Keep vnstatd defaults; hosts may override ExecStart if needed.
}
