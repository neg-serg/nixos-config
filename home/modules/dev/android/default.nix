{
  lib,
  pkgs,
  config,
  ...
}:
with lib;
  mkIf config.features.dev.enable {
    home.packages = config.lib.neg.pkgsList [
      pkgs.adbfs-rootless # FUSE filesystem for ADB (rootless on device)
      pkgs.adbtuifm # TUI-based file manager for ADB
      pkgs.android-tools # Android platform tools (adb, fastboot)
      pkgs.fuse3 # provides fusermount3 needed by adbfs-rootless
      pkgs.scrcpy # control Android device from PC
    ];
  }
