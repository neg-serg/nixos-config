##
# Module: user/nix-maid/sys/user-services/flake-bump
# Purpose: run scripts/dev/flake-bump-own.sh weekly from the user manager. The
# script bumps the flake inputs that point at neg's own repositories, keeps only
# the bumps whose toplevel evaluation passes, and commits flake.lock locally
# (never pushes); rollout-watch deploys that commit on its next tick.
#
# Why the user manager: the bump needs neg's git identity and network access,
# and `nix flake update` / `nix eval` run as the user, not as root. The unit is
# hand-rolled like rollout-watch's: lib/systemd-user.nix's mkOneshotTimer emits
# system units (`systemd.services`), which would run the commit as root.
#
# Quirks:
#   - the wrapper runs the LIVE checkout (features.system.flakeBump.repo), not
#     the store copy of the script: the script commits into that checkout and
#     reads its .git, which a store copy does not have. Same reason
#     rollout-watch addresses the live repo by string;
#   - --allow-skip keeps a tick quiet when the tree is dirty or another branch is
#     checked out (a human or an agent is working); a failed eval still exits
#     non-zero and shows up in `systemctl --user --failed`;
#   - Restart = "no": a failing input must not be retried every RestartSec until
#     the next weekly tick;
#   - Persistent = false, like the other user timers: a missed Sunday 04:00 is
#     skipped instead of firing a catch-up burst at the next boot.
#
# Key options: features.system.flakeBump.{enable,repo,calendar,heavy}
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.features.system.flakeBump;

  args = lib.optionalString cfg.heavy " --all" + " --allow-skip";

  # The script and the eval gate shell out to git/jq/sed/awk/find/grep, so the
  # oneshot gets an explicit PATH instead of the user manager's minimal one.
  bump = pkgs.writeShellApplication {
    name = "flake-bump-own";
    runtimeInputs = [
      config.nix.package # nix flake update / nix eval
      pkgs.bash # the live script's `#!/usr/bin/env bash`
      pkgs.git # branch/status/commit, the eval gate's tree hashing
      pkgs.jq # flake.lock revisions
      pkgs.coreutils # cp/mktemp/tail/sha256sum/readlink/stat
      pkgs.gnused # eval gate output trimming
      pkgs.gawk # the script's --help header
      pkgs.gnugrep # eval gate's file scans
      pkgs.findutils # eval gate's file discovery
    ];
    text = ''
      exec "${cfg.repo}/scripts/dev/flake-bump-own.sh"${args}
    '';
  };
in
lib.mkIf cfg.enable {
  systemd.user.services.flake-bump-own = {
    description = "Bump neg's own flake inputs and commit flake.lock";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = lib.getExe bump;
      WorkingDirectory = cfg.repo;
      # A failing eval must not loop; the next weekly tick retries from HEAD.
      Restart = "no";
    };
  };

  systemd.user.timers.flake-bump-own = {
    description = "Weekly bump of own flake inputs";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = cfg.calendar;
      Unit = "flake-bump-own.service";
      Persistent = false;
    };
  };
}
