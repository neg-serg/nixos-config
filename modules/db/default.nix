{lib, config, pkgs, ...}: let
  enabled = config.features.dev.enable or false;
  packages = [
    pkgs.sqlite # self-contained, serverless SQL DB
    pkgs.pgcli # PostgreSQL TUI client
    pkgs.iredis # Redis enhanced CLI
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
