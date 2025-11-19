{
  lib,
  config,
  ...
}:
lib.mkIf config.features.dev.enable {
  # Git CLI helpers now install systemwide; module retained for future HM-only bits.
}
