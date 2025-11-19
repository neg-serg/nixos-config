{lib, config, ...}:
lib.mkIf (config.features.dev.enable && config.features.hack.enable) {
  # SDR toolchain now installs system-wide via modules/dev/hack/sdr.nix.
}
