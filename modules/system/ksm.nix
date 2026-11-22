##
# Module: system/ksm
# Purpose: `ksmctl` — the switch and the counters for the kernel's same-page
#   merging (KSM).
#
# KSM merges identical anonymous pages, but only inside ranges a process
# registered with madvise(MADV_MERGEABLE); QEMU/KVM and emulator runtimes
# register guest RAM, ordinary desktop processes register nothing. That is why
# there is no `hardware.ksm.enable` here: on trantor a permanently running ksmd
# would scan an empty set. `ksmctl run -- CMD...` enables the daemon for one
# workload and restores the previous state afterwards, and `ksmctl status`
# shows what was actually merged (pages_sharing, general_profit, cow_ksm).
#
# The sysfs switch never survives a reboot, so nothing in this module changes
# boot state. A future VM host that wants KSM always on is one line away:
# `hardware.ksm.enable = true`.
{
  pkgs,
  lib,
  ...
}:
{
  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "ksmctl";
      runtimeInputs = [
        pkgs.coreutils # cat: read the sysfs state and counters
        pkgs.gawk # scan-rate and saved-memory arithmetic
      ];
      # The file keeps its own shebang so shellcheck can lint it standalone;
      # writeShellApplication adds one, so drop the duplicate here.
      text = lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./ksmctl.sh);
    })
  ];
}
