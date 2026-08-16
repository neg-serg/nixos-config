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
          default = [
            "kitty" # terminal: all TUIs get us, so bare-letter hotkeys work everywhere
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
