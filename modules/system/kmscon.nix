# kmscon: a userspace VT console on KMS/DRM instead of the in-kernel one.
#
# What it covers: systemd-logind spawns autovt@ttyN on every VT switch for
# tty1..NAutoVTs (upstream default 6), and the NixOS kmscon module aliases
# autovt@ to kmsconvt@, so what appears on tty2-tty6 is kmscon: a real font,
# full color, UTF-8 glyphs and scrollback, with agetty running inside it.
#
# What it deliberately does not cover:
# - tty1: greetd starts the Hyprland session there and the login screen is a
#   pleamar lock scene inside that compositor (modules/user/session/greetd.nix).
#   A console on the same VT would fight it for DRM master. The module only
#   pulls kmsconvt@tty1 into getty.target when no display manager is enabled,
#   and greetd sets services.displayManager.enable — so tty1 is untouched.
# - tty8 and tty10-tty16: the journal viewers of modules/system/log-ttys.nix
#   write to /dev/ttyN and depend on the kernel console painting that output.
#   kmscon renders into its own framebuffer, so such a write would be
#   invisible. Those VTs are above NAutoVTs, so logind never spawns kmscon
#   there.
#
# Rendering is software (drm2d). The OpenGL path (kmscon.conf `hwaccel`) needs
# a working GBM/EGL stack on the DRM master kmscon owns, and a console that
# fails to start costs the maintenance path itself, while a console at 4K that
# copies a framebuffer is merely not accelerated. Turn hwaccel on only after
# seeing the software console work.
{ config, lib, ... }:
let
  inherit (lib) mkForce mkIf;
  cfg = config.features.system.kmscon;
in
{
  config = mkIf cfg.enable {
    services.kmscon = {
      enable = true;

      config = {
        hwaccel = false; # software blit; see the header for the tradeoff
        # Family name of the Iosevka nerd build from modules/fonts. The module
        # asserts fontconfig is enabled whenever font-name is set. font-size
        # stays at its default 0, which makes kmscon pick a size from the
        # monitor resolution.
        font-name = "Iosevka";
        # Same layout pair as the compositor (files/gui/hypr/hyprland.lua,
        # kb_layout = "us,ru"). Alt+Shift instead of Super+S because the
        # console has no compositor keybinds.
        xkb-layout = "us,ru";
        xkb-options = "grp:alt_shift_toggle";
      };
    };

    # kmsconvt@ carries OnFailure=getty@%i.service, but the module masks
    # getty@.service, which would make that safety net dead: a kmscon that
    # cannot start would leave the VT with nothing on it. Nothing else pulls
    # getty@ in on this host — getty.target wants no instance while a display
    # manager is enabled, and logind's autovt@ alias resolves to kmsconvt@ —
    # so unmasking it only arms the fallback.
    systemd.suppressedSystemUnits = mkForce [ ];
  };
}
