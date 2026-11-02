{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.features.gui;
  # Module-shaped systemd user units (lib/systemd-user.nix)
  systemdUser = config.lib.neg.systemdUser;
in
lib.mkIf (cfg.enable or false) {
  # The host is the only Genelec path left: `genlc daemon` owns the GLM adapter,
  # keeps GLM's own cycle alive (probe, lease, poll every ~0.57 s) so the
  # monitors never drop their sessions, and serves the Unix socket the CLI uses
  # for status/volume/mute. The Windows VM, the OSC bridge, the MIDI relay and
  # the adapter-placement helpers that used to live here are gone (2026-11,
  # .agent/notes/2026-11-02-glm-vm-removal-backlog.md).
  systemd.user.services.genlc = systemdUser.mkUserService {
    presets = [
      # Started with the user manager, not with the compositor: the daemon owns
      # the adapter and keeps the GLM leases, so it must outlive a Hyprland
      # restart and not wait for a graphical session to appear.
      "defaultWanted"
      "restartOnFailure"
    ];
    description = "Genelec SAM daemon: adapter owner, lease cycle, Unix-socket control";
    serviceConfig = {
      ExecStart = "${lib.getExe pkgs.genlc} daemon";
      RestartSec = 3;
    };
  };
}
