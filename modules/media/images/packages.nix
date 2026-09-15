##
# Module: media/images/packages
# Purpose: Provide image editing/recovery/metadata tooling system-wide.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  enabled = config.lib.neg.enabled "gui";
  packages = [
    # -- Color --
    pkgs.lutgen # procedurally render LUTs for stylizing

    pkgs.pastel # extract palettes / simulate colorblindness

    # -- Compression / Optimization --
    pkgs.advancecomp # recompress ZIP/PNG aggressively
    pkgs.jpegoptim # lossy JPEG optimizer better than jpegtran
    pkgs.optipng # lossless PNG optimizer
    pkgs.pngquant # perceptual PNG quantizer for quicksharing
    pkgs.scour # SVG minifier to shrink UI assets

    # -- Metadata --
    pkgs.exiftool # swiss-army EXIF inspector used in scripts
    pkgs.exiv2 # CLI for editing EXIF/IPTC/XMP metadata
    pkgs.mediainfo # dump container/codec metadata for photos/videos

    # -- Misc --
    pkgs.graphviz # render contact sheets / graph exports via dot

    # -- QR / Barcode --
    pkgs.qrencode # generate QR codes for wallpaper/text overlays

    # -- Viewer --
    pkgs.swayimg # primary image viewer with IPC hooks (launched via `sx`)
  ];
in
{
  config = lib.mkIf enabled {
    environment.systemPackages = lib.mkAfter packages;
  };
}
