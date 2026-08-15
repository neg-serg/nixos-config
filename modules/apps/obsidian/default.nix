{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "apps.obsidian";
in
lib.mkIf enabled {
  environment.systemPackages = [
    pkgs.obsidian # Knowledge base and note-taking application
  ];

  users.users.neg.maid.file.home.".local/share/obsidian".source = ../../../files/obsidian-vault;
}
