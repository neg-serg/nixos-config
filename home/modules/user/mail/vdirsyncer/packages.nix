{
  lib,
  config,
  ...
}:
with lib;
  mkIf (config.features.mail.enable && config.features.mail.vdirsyncer.enable) {
    # vdirsyncer binary ships system-wide now; module retained for future
    # Home Manager tweaks (dirs, systemd units, configs).
  }
