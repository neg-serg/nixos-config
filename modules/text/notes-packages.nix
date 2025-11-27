##
# Module: text/notes-packages
# Purpose: Provide notes/knowledge management CLIs system-wide.
{
  lib,
  config,
  pkgs,
  ...
}: let
  enabled = config.features.text.notes.enable or false;
  packages = [
    pkgs.zk # Zettelkasten CLI
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
