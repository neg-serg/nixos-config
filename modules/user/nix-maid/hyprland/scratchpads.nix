{
  lib,
  pkgs,
  ...
}:
let
  pyprlandConfig = {
    pyprland.plugins = [
      "fetch_client_menu"
      "scratchpads"
      "toggle_special"
    ];
    scratchpads = {
      im = {
        animation = "";
        command = "${lib.getExe pkgs.telegram-desktop}"; # Telegram Desktop messaging app
        class = "org.telegram.desktop";
        size = "30% 95%";
        position = "69% 2%";
        lazy = true;
        multi = true;
        process_tracking = false; # Telegram is single-instance
      };
      music = {
        animation = "";
        command = "${lib.getExe pkgs.kitty} --class music -e ${lib.getExe pkgs.rmpc}"; # Fast, feature-rich, GPU based terminal emulator | TUI music player client for MPD with album art support vi...
        margin = "80%";
        class = "music";
        position = "15% 50%";
        size = "70% 40%";
        lazy = true;
        unfocus = "hide";
        process_tracking = false;
      };
      torrment = {
        animation = "";
        command = "${lib.getExe pkgs.kitty} --class torrment -e ${lib.getExe pkgs.neg.tewi}"; # Fast, feature-rich, GPU based terminal emulator
        class = "torrment";
        position = "1% 0%";
        size = "98% 40%";
        lazy = true;
        unfocus = "hide";
        process_tracking = false;
      };
      teardown = {
        animation = "";
        command = "${lib.getExe pkgs.kitty} --class teardown -e ${lib.getExe pkgs.btop}"; # Fast, feature-rich, GPU based terminal emulator
        class = "teardown";
        position = "1% 0%";
        size = "98% 50%";
        lazy = true;
        process_tracking = false;
      };
      mixer = {
        animation = "fromRight";
        command = "${lib.getExe pkgs.kitty} --class mixer -e ${lib.getExe pkgs.ncpamixer}"; # Fast, feature-rich, GPU based terminal emulator | Terminal mixer for PulseAudio inspired by pavucontrol
        class = "mixer";
        lazy = true;
        size = "40% 90%";
        unfocus = "hide";
        multi = true;
        process_tracking = false;
      };
    };
  };

  tomlFormat = pkgs.formats.toml { };
in
{
  pyprlandToml = tomlFormat.generate "pyprland.toml" pyprlandConfig;
}
