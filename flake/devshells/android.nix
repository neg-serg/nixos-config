{
  pkgs,
  lib,
  ...
}:
pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.android-tools # Android ADB and fastboot tools
    pkgs.scrcpy # Display and control Android devices over USB or TCP/IP
    pkgs.adbfs-rootless # Mount Android devices via FUSE filesystem
    pkgs.adbtuifm # TUI file manager for Android over ADB
  ]
  ++ lib.optionals (pkgs ? fuse3) [ pkgs.fuse3 ]; # Library that allows filesystems to be implemented in user...
}
