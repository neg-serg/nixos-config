##
# Module: media/images/packages
# Purpose: Provide image editing/recovery/metadata tooling and swayimg wrappers system-wide.
{lib, config, pkgs, ...}: let
  enabled = config.features.gui.enable or false;
  swayimgFirst = pkgs.writeShellScriptBin "swayimg-first" (
    let
      tpl = builtins.readFile ./swayimg-first.sh;
      replacements = [
        (lib.getExe pkgs.swayimg)
        (lib.getExe pkgs.socat)
      ];
    in
      lib.replaceStrings ["@SWAYIMG_BIN@" "@SOCAT_BIN@"] replacements tpl
  );
  packages = [
    pkgs.exiftool
    pkgs.exiv2
    pkgs.mediainfo
    pkgs.testdisk-qt
    pkgs.gimp
    pkgs.darktable
    pkgs.rawtherapee
    pkgs.graphviz
    pkgs.jpegoptim
    pkgs.optipng
    pkgs.pngquant
    pkgs.advancecomp
    pkgs.scour
    pkgs.pastel
    pkgs.lutgen
    pkgs.qrencode
    pkgs.zbar
    pkgs.swayimg
    swayimgFirst
    pkgs.viu
  ];
in {
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
