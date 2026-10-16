##
# Module: nix/prune-generations
# Purpose: cap the number of system generations. Every `nixos-rebuild switch`
# adds one, and every generation is a GC root for its whole system closure, so
# an uncapped profile grows the store by tens of gigabytes (trantor reached 483
# generations before a manual trim, Oct 2026). nix.gc's `--delete-older-than
# 21d` cannot help there: on a machine that rebuilds several times a day every
# generation is younger than the window.
# Retention: the newest 25, deliberately the same count as the systemd-boot menu
# (boot.loader.systemd-boot.configurationLimit in modules/system/boot.nix), so the
# boot entries and the profile links stay in step. nix.gc then frees what the
# dropped generations were pinning.
# Key options: features.system.generationPrune.enable (default true).
# Dependencies: config.nix.package (nix-env), neg.systemdUser.mkOneshotTimer.
{
  lib,
  config,
  pkgs,
  neg,
  ...
}:
let
  inherit (lib)
    mkIf
    getExe
    getExe'
    ;
  cfg = config.features.system.generationPrune;
  systemdUser = neg.systemdUser lib;

  # Keep in sync with boot.loader.systemd-boot.configurationLimit.
  keep = 25;

  pruneScript = pkgs.writeShellApplication {
    name = "nix-prune-generations";
    runtimeInputs = [ config.nix.package ]; # nix-env from the same nix the daemon runs
    text = ''
      set -euo pipefail

      profile=/nix/var/nix/profiles/system
      # "+N" = keep the newest N generations, delete the rest. The current
      # generation is always the newest, so activation cannot be broken.
      ${getExe' config.nix.package "nix-env"} -p "$profile" --delete-generations "+${toString keep}"
    '';
  };
in
{
  config = mkIf cfg.enable (
    systemdUser.mkOneshotTimer {
      name = "nix-prune-generations";
      description = "Drop system generations beyond the newest ${toString keep}";
      timerDescription = "Prune old system generations daily";
      script = getExe pruneScript;
      onCalendar = "daily";
      networkOnline = false;
      restart = null; # a missed prune is retried tomorrow, not in a minute
    }
  );
}
