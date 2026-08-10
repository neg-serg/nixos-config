{
  pkgs,
  ...
}:
pkgs.mkShell {
  packages = [
    pkgs.iredis # Redis enhanced CLI
    pkgs.pgcli # PostgreSQL TUI client
    pkgs.sqlite # self-contained, serverless SQL DB
  ];
}
