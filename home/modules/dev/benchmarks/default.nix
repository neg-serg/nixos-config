{lib, config, ...}:
lib.mkIf config.features.dev.enable {
  # Benchmark utilities now install via modules/dev/benchmarks/default.nix.
}
