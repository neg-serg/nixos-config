{
  lib,
  config,
  pkgs,
  ...
}:
let
  devEnabled = config.features.dev.enable or false;
  packages = [
    pkgs.memtester # user-space memory stress test for bad DIMMs
    pkgs.rewrk # HTTP benchmarking tool with low jitter
    pkgs.stress-ng # multi-subsystem stress tester
    pkgs.wrk2 # latency-focused HTTP benchmark
  ];
in
{
  config = lib.mkIf devEnabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
