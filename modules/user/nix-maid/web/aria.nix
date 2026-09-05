{
  lib,
  config,
  ...
}:
{
  # aria2 config + systemd user service are owned by sys/services-manual.nix
  # (single source of truth). This module used to write a *duplicate*
  # .config/aria2/aria2.conf alongside services-manual.nix, which produced a
  # doubled config file on disk — the duplication is removed here.
  # The aria2 binary itself is installed via cli/file-ops.nix.
  config = lib.mkIf (config.lib.neg.enabled "web" && config.lib.neg.enabled "web.tools") { };
}
