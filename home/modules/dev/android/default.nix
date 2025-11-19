{
  lib,
  config,
  ...
}:
lib.mkIf config.features.dev.enable {
  # Android tooling (adbfs, scrcpy, etc.) now provided by system-wide modules.
}
