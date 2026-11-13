##
# Module: system/systemd/resource-policy
# Purpose: bound the user-space resource classes without capping individual
# applications. Two facts shape this:
#
#   1. systemd 262 has no DefaultMemoryMax/DefaultCPUQuota for the manager —
#      only DefaultMemoryAccounting, DefaultTasksMax and the pressure watches.
#      A blanket per-unit cap therefore does not exist as an option.
#   2. GUI apps started by the compositor share one login-session scope
#      (`session-1.scope`), so a ceiling there would be a ceiling on the whole
#      desktop. Per-app cgroups exist only for units and `systemd-run` scopes.
#
# Hence: cap the slices that classify units that *are* separate cgroups, and
# leave interactive apps alone.
#
#   app.slice         soft ceiling only (MemoryHigh + MemorySwapMax). No
#                     MemoryMax: the bar, notifications, camilladsp and the
#                     window-manager helpers live here, and a kill costs the
#                     session. High throttles by reclaim instead.
#   background.slice  hard ceiling for daemons with no interactive peak
#                     (downloads, crawler, removable-media mounting). Units opt
#                     in with `serviceConfig.Slice = "background.slice"`.
#
# games.slice is a SYSTEM-level slice (modules/user/games/performance.nix) and
# stays untouched: games keep the whole machine, and the user-manager policy
# below cannot reach a system slice anyway.
#
# CPU: no quotas on interactive units — builds, renders and games need bursts.
# Class priority is already expressed by CPUWeight (background.slice defaults
# to 30). Only the background class gets a quota, where a burst is never
# legitimate.
# Notes:   MemoryHigh throttles before MemoryMax kills, so High is enough for
#          the app class. MemorySwapMax matters more than MemoryMax here: the
#          host has a 507G swap partition, and without a swap cap a runaway app
#          thrashes for hours instead of hitting the ceiling that would slow it
#          down. MemoryMin on the critical units is their protection — reclaim
#          picks the small cgroups first (the measured case is in
#          modules/user/nix-maid/gui/pleamar.nix).
##
{ lib, ... }:
{
  systemd.user.slices = {
    app = {
      description = "Application Slice (bounded)";
      sliceConfig = {
        MemoryHigh = "40G";
        MemorySwapMax = "12G";
      };
    };

    background = {
      description = "Background Slice (bounded)";
      sliceConfig = {
        # High throttles, Max kills. The crawler runs a real browser in
        # rootless podman, and a page with heavy JS can hold several GB and all
        # the cores it gets: 6G/12G and 4 cores leave the crawler comfortable
        # while still keeping the class away from the interactive work.
        MemoryHigh = "6G";
        MemoryMax = "12G";
        MemorySwapMax = "2G";
        CPUQuota = "400%";
      };
    };
  };

  # devmon is declared by nixpkgs as a user service and defaults to app.slice.
  # Removable-media mounting has no interactive peak, so it belongs in the
  # bounded background class.
  systemd.user.services.devmon.serviceConfig.Slice = lib.mkDefault "background.slice";
}
