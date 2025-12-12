{
  lib,
  config,
  pkgs,
  ...
}: let
  enabled = config.features.dev.enable or false;
  packages = [
    pkgs.iredis # Redis enhanced CLI
    pkgs.pgcli # PostgreSQL TUI client
    pkgs.sqlite # self-contained, serverless SQL DB
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
