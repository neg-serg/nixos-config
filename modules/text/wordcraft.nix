##
# Module: text/wordcraft
# Purpose: WordCraft — Word-style word processor for .docx/.odt/.rtf, plus the
# `wordcraft-cli` document converter that ships in the same package.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "text.wordcraft";
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter [
      pkgs.wordcraft # WordCraft: desktop word processor + wordcraft-cli converter (docx/pdf/odt/rtf/md/…)
    ];
  };
}
