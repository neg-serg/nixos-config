##
# Module: user/nix-maid/sys/user-services/podman-prune
# Purpose: keep rootless podman storage bounded. Stopped containers keep their
# writable layers (trantor held 3.5G in two containers stopped weeks earlier) and
# rebuilds leave untagged layers behind. A daily prune drops stopped
# containers older than a week and untagged images; running containers and
# tagged images are never touched — `-a` is deliberately absent, so base
# images used by distrobox survive.
# Key options: none — gated by features.virt.docker, the flag that brings the
# podman stack in.
# Dependencies: pkgs.podman in the wrapper's PATH; rootless storage lives in
# ~/.local/share/containers, so the unit runs as the user, not as root.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    getExe
    ;
  enabled = config.lib.neg.enabled "virt.docker";

  pruneScript = pkgs.writeShellApplication {
    name = "podman-prune";
    runtimeInputs = [
      pkgs.podman # podman itself: it owns the storage being pruned
      pkgs.coreutils # standard utilities for the wrapper's shell
    ];
    text = ''
      set -euo pipefail

      # Stopped containers older than a week; running ones are never touched.
      podman container prune --force --filter "until=168h"
      # Untagged layers only; tagged images survive without -a.
      podman image prune --force
    '';
  };
in
mkIf enabled {
  systemd.user.services.podman-prune = {
    description = "Prune stopped podman containers and untagged images";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = getExe pruneScript;
    };
  };

  systemd.user.timers.podman-prune = {
    description = "Timer: prune podman debris daily";
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "45m";
      Persistent = true;
      Unit = "podman-prune.service";
    };
    wantedBy = [ "timers.target" ];
  };
}
