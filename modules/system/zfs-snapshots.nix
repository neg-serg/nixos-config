##
# Module: system/zfs-snapshots
# Purpose: local ZFS snapshot policy (sanoid) for the datasets that hold data
# no one can re-download: home + root, doc, mail, music, vid. Covers the "rm
# the wrong thing", "script half-overwrote a file" and "app corrupted its
# store" class of accidents, which pool health checks and scrub do not.
#
# Scope is deliberately narrow:
#   - tank/store (/nix/store) is excluded: snapshots would pin every GC'd path
#     for the whole retention window, and the store is regenerable anyway.
#   - zero/ai (models), zero/torrent, gamez/main (games) are re-downloadable;
#     gamez also churns constantly (Steam), so its snapshots would hold
#     gigabytes of dead blocks.
#
# Implementation note: upstream services.sanoid hands snapshot rights to a
# DynamicUser `sanoid`, but `zfs allow sanoid …` cannot resolve a dynamic user,
# so the unit's ExecStartPre fails (nixpkgs services/backup/sanoid.nix sets
# DynamicUser = true while ExecStartPre runs as the unit user). Running sanoid
# as root removes both the delegation steps and the failure mode.
#
# Key options: features.system.zfsSnapshots.enable (default true).
# Dependencies: pkgs.sanoid via services.sanoid; pools are imported after boot
# by modules/system/filesystems.nix, and the unit orders itself after zfs.target.
{
  lib,
  config,
  ...
}:
let
  inherit (lib)
    mkIf
    mkForce
    ;
  cfg = config.features.system.zfsSnapshots;

  # ≤68 snapshots per dataset (24 hourly + 30 daily + 8 weekly + 6 monthly);
  # autoprune drops the older ones in the same run, so the count is bounded.
  userdataTemplate = {
    frequently = 0;
    hourly = 24;
    daily = 30;
    weekly = 8;
    monthly = 6;
    yearly = 0;
    autosnap = true;
    autoprune = true;
  };
in
{
  config = mkIf cfg.enable {
    services.sanoid = {
      enable = true;
      interval = "hourly"; # snapshot and prune cadence
      templates.userdata = userdataTemplate;
      datasets = {
        # / — home, dotfiles, /etc, /var (everything not on its own dataset)
        "tank/nixos".useTemplate = [ "userdata" ];
        "zero/doc".useTemplate = [ "userdata" ]; # ~/doc
        "zero/mail".useTemplate = [ "userdata" ]; # ~/.local/mail (maildir)
        "zero/music".useTemplate = [ "userdata" ]; # ~/music
        "zero/vid".useTemplate = [ "userdata" ]; # ~/vid
      };
    };

    # Root-run, no per-dataset delegation — see the implementation note above.
    systemd.services.sanoid.serviceConfig = {
      DynamicUser = mkForce false;
      User = mkForce "root";
      Group = mkForce "root";
      ExecStartPre = mkForce [ ];
      ExecStopPost = mkForce [ ];
    };
  };
}
