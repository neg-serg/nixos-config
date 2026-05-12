# Module: media/images/photo
# Purpose: Photography workflow tools (optional feature)
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.features.media.photo;
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.darktable # RAW editor/dam tailored to photographers
      pkgs.rawtherapee # alternative RAW developer (non-destructive)
      pkgs.testdisk-qt # photorec GUI for image recovery
    ];
  };
}
