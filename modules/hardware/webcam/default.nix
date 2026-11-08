{ pkgs, config, ... }:
let
  # scrcpy drags a 1.0 GiB closure (SDL, ffmpeg and its own pinned
  # android-tools adb) for a tool started a few times a week; the launcher
  # builds it on first use and GC-roots it under $HOME instead.
  onDemand = config.lib.neg.onDemand pkgs;
in
{
  environment.systemPackages = [
    (onDemand {
      name = "scrcpy";
      attr = "scrcpy";
    }) # Android device display/control over USB/TCP, built on first use
  ];
}
