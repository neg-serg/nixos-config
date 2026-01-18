##
# Module: media/images/packages
# Purpose: Provide image editing/recovery/metadata tooling and swayimg wrappers system-wide.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.features.gui.enable or false;
  swayimgFirst = pkgs.writeShellScriptBin "swayimg-first" (
    let
      tpl = builtins.readFile ./swayimg-first.sh;
      replacements = [
        (lib.getExe pkgs.swayimg) # Image viewer for Sway/Wayland
        (lib.getExe pkgs.socat) # Utility for bidirectional data transfer between two indep...
      ];
    in
    lib.replaceStrings [ "@SWAYIMG_BIN@" "@SOCAT_BIN@" ] replacements tpl
  );
  packages = [
    # -- Color --
    pkgs.lutgen # procedurally render LUTs for stylizing
    pkgs.neg.richcolors # render palette image from hex code file
    pkgs.pastel # extract palettes / simulate colorblindness

    # -- Compression / Optimization --
    pkgs.advancecomp # recompress ZIP/PNG aggressively
    pkgs.jpegoptim # lossy JPEG optimizer better than jpegtran
    pkgs.optipng # lossless PNG optimizer
    pkgs.pngquant # perceptual PNG quantizer for quicksharing
    pkgs.scour # SVG minifier to shrink UI assets

    # -- Editors --


    # -- Metadata --
    pkgs.exiftool # swiss-army EXIF inspector used in scripts
    pkgs.exiv2 # CLI for editing EXIF/IPTC/XMP metadata
    pkgs.mediainfo # dump container/codec metadata for photos/videos

    # -- Misc --
    pkgs.graphviz # render contact sheets / graph exports via dot

    # -- QR / Barcode --
    pkgs.qrencode # generate QR codes for wallpaper/text overlays
    pkgs.zbar # CLI barcode/QR scanner for verification

    # -- Viewer --
    pkgs.swayimg # primary image viewer with IPC hooks
    pkgs.viu # terminal image preview helper for scripts
    swayimgFirst # wrapper that ensures swayimg session state
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
