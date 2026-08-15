{
  lib,
  config,
  pkgs,
  ...
}:
let
  devEnabled = config.lib.neg.enabled "dev";
  packages = [
    pkgs.memtester # user-space memory stress test for bad DIMMs
    pkgs.rewrk # HTTP benchmarking tool with low jitter
    pkgs.wrk2 # latency-focused HTTP benchmark
  ];
in
{
  config = lib.mkIf devEnabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
