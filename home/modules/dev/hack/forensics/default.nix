{lib, config, ...}:
lib.mkIf (config.features.dev.enable && config.features.hack.enable) {
  # Forensics packages now live in modules/dev/hack/forensics.nix.
}
