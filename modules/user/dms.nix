# DankMaterialShell (DMS) — DankLinux's Quickshell-based desktop shell, taken from
# the nixpkgs program module (`programs.dms-shell`, pkgs.dms-shell 1.6.x).
#
# Autostart is deliberately off. This session already runs its own Quickshell panel
# (modules/user/nix-maid/gui/quickshell.nix, quickshell.service) and DMS is a full
# second shell: both want the bar space and the notification bus
# (org.freedesktop.Notifications). Install-only keeps the trial reversible; run it
# by hand in a terminal:
#
#   systemctl --user stop quickshell.service   # free the session for DMS
#   dms run                                    # start DankMaterialShell
#   systemctl --user start dms                 # same thing, under journald
#                                              # (the unit ships with the package
#                                              # but stays disabled: no autostart)
#
# Skip `dms setup` for now: it rewrites compositor keybinds/colors, and those files
# are nix-maid symlinks owned by this repo.
{
  config,
  lib,
  ...
}:
{
  config = lib.mkIf (config.lib.neg.enabled "gui.dms") {
    programs.dms-shell = {
      enable = true; # installs dms + its Quickshell, matugen, cava
      # The package ships dms.service either way, but with this off the unit is
      # never enabled/wanted: nothing autostarts it at login, so quickshell.service
      # keeps owning the session until someone starts DMS by hand.
      systemd.enable = false;
    };
  };
}
