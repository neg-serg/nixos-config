{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.features.apps.obsidian.enable or false;
in
lib.mkIf enabled {
  environment.systemPackages = [
    pkgs.obsidian # Knowledge base and note-taking application
  ];

  users.users.neg.maid.file.home.".local/share/obsidian".source = ../../../files/obsidian-vault;
}
