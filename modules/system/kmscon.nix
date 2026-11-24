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
# Rendering uses the GL/GBM path (drm3d + gltex) since 2026-11-24, after the
# software console (drm2d) had been verified working. kmscon itself falls back
# to drm2d if the GL device cannot be created, and kmsconvt@'s
# OnFailure=getty@%i.service keeps the VT usable if the whole console fails.
# Set hwaccel = false to return to the software blit.
#
# Console hotkeys (kmscon grabs; session-control is enabled below):
# - Shift+PgUp/PgDn page the scrollback, Shift+Up/Down scroll one line;
# - Ctrl+= / Ctrl+- (and the keypad +/-) zoom the font;
# - Ctrl+Super+Left/Right switch kmscon sessions, Ctrl+Super+Enter opens one,
#   Ctrl+Super+Backspace closes the current one (session-control);
# - Ctrl+Alt+F1..F12 switch VTs (kmscon's VT backend);
# - Alt+Shift and Super+Space toggle the us/ru layout.
#
# Video mode: the VT defaults to the last DRM_MODE_TYPE_PREFERRED mode on the
# connector. DP-2 advertises both 4K240 and 4K60 as preferred, so the console
# stayed at 60 Hz; the config forces 4K240. The kernel reports the panel's
# 239.99 Hz mode as vrefresh=240, and kmscon matches that integer exactly.
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
        hwaccel = true; # GL/GBM (drm3d+gltex); drm2d is the internal fallback

        # kmscon's default picks the last DRM_MODE_TYPE_PREFERRED mode, and this
        # panel advertises both 4K240 and 4K60 as preferred, so the VT stayed at
        # 60 Hz. Force the mode the compositor runs; the kernel's vrefresh for
        # the 239.99 Hz mode is 240 and kmscon matches that integer exactly.
        mode = "[DP-2]3840x2160@240";

        # Family name of the Iosevka nerd build from modules/fonts. The module
        # asserts fontconfig is enabled whenever font-name is set. font-size
        # stays at its default 0, which makes kmscon pick a size from the
        # monitor resolution.
        font-name = "Iosevka";
        # Same layout pair as the compositor (files/gui/hypr/hyprland.lua,
        # kb_layout = "us,ru"). The compositor switches with a Hyprland bind;
        # the console gets these two XKB toggles instead.
        xkb-layout = "us,ru";
        xkb-options = "grp:alt_shift_toggle,grp:win_space_toggle";
        # 50 ms (20 cps) is sluggish for a terminal; match the compositor's
        # kb_repeat_delay/kb_repeat_rate (250 ms / 28 ms).
        xkb-repeat-delay = 250;
        xkb-repeat-rate = 30;

        # kmscon's own TERM name is unknown to remote hosts; xterm-256color is
        # understood everywhere and keeps 256 colours.
        term = "xterm-256color";
        # 1000 lines is barely one screen; 10k is cheap at the 4K auto font.
        sb-size = 10000;

        # Without this flag kmscon leaves the Ctrl+Super session grabs dead.
        session-control = true;

        # The default zoom-in grab is <Ctrl>Plus, but the grab matcher compares
        # the modifier set exactly: on a US layout plus requires Shift, so
        # Ctrl+Shift+= never matches. Use the unshifted equal and the keypad plus.
        grab-zoom-in = "<Ctrl>equal,<Ctrl>KP_Add";
        grab-zoom-out = "<Ctrl>minus,<Ctrl>KP_Subtract";
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
