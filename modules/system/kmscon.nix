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
#
# Palette: the console mirrors the default shell theme (variant 1,
# files/shell/theme/v1/kitty.conf; the shell-theme `current` link is unset, so
# kitty runs v1). kmscon takes the 16 ANSI slots plus fg/bg — the custom
# 256-colour ladder, selection and cursor colours have no kmscon equivalent.
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
        # asserts fontconfig is enabled whenever font-name is set.
        font-name = "Iosevka";
        # 32 px matches the kitty setup (Iosevka at 12 pt on the scale-2 4K
        # monitor). The auto size was 54 px at 3840x2160 and looked too large;
        # Ctrl+=/- still zoom at runtime.
        font-size = 32;

        # kmscon's built-in palette is not the shell theme. Mirror the 16 ANSI
        # slots of files/shell/theme/v1/kitty.conf (hex converted to the r,g,b
        # bytes kmscon parses); the custom 256-colour ladder, selection and
        # cursor colours from files/kitty/theme.conf have no kmscon equivalent.
        palette = "custom";
        palette-black = "2,2,2";
        palette-red = "138,47,88";
        palette-green = "40,115,115";
        palette-yellow = "145,78,137";
        palette-blue = "57,85,115";
        palette-magenta = "94,70,140";
        palette-cyan = "49,101,140";
        palette-light-grey = "137,156,161";
        palette-dark-grey = "61,61,61";
        palette-light-red = "207,79,136";
        palette-light-green = "83,166,166";
        palette-light-yellow = "191,133,204";
        palette-light-blue = "71,122,179";
        palette-light-magenta = "126,98,179";
        palette-light-cyan = "96,150,191";
        palette-white = "97,114,135";
        palette-foreground = "108,126,150";
        palette-background = "0,0,0";
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
