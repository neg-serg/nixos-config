{
  lib,
  mkBool,
  ...
}:
with lib;
{
  options.features = {
    hardware = {
      bluetooth.enable = mkBool "enable Bluetooth support" false;

      usbAutomount.enable = lib.mkEnableOption ''
        Enable udev-driven USB storage auto-mount via systemd service (mounts under /mnt/<label>).
      '';
    };
    input = {
      kanata.enable = mkBool "enable Kanata keyboard remapper (requires uinput module)" false;

      ruHotkeys = {
        enable = mkBool "enable per-window keyboard layout switching (us in hotkey-heavy apps)" false;

        usClasses = mkOption {
          type = types.listOf types.str;
          # Terminal windows are launched with custom kitty classes (M4+* scratch
          # binds in files/gui/hypr/hyprland.lua) — keep this list in sync.
          default = [
            "term" # plain shell (kitty --class term)
            "nwim" # nvim wrapper (kitty --class nwim)
            "music" # rmpc (M4+f)
            "teardown" # btop (M4+d)
            "torrment" # rustmission (M4+t)
            "vpn" # tun status (M4+u)
            "mixer" # ncpamixer (M4+C+p)
            "rebuild" # nh os switch (M4+S+n)
            "mpd-add" # rmpc spawns this class
            "mpv" # video player: no text input, vim-style keys
          ];
          description = ''
            Hyprland window classes forced to the us layout on focus. Everything
            else defaults to ru (typing-first). Switching happens only on focus
            transitions — a manual M4+S switch stays until the next focus change.
          '';
        };

        usLayoutIndex = mkOption {
          type = types.int;
          default = 0;
          description = "XKB group index of the us layout (kb_layout = us,ru invariant).";
        };

        ruLayoutIndex = mkOption {
          type = types.int;
          default = 1;
          description = "XKB group index of the ru layout (kb_layout = us,ru invariant).";
        };

        pollSec = mkOption {
          type = types.str;
          default = "0.5";
          description = "Active-window poll interval in seconds (fractional values allowed).";
        };
      };
    };
  };
}
