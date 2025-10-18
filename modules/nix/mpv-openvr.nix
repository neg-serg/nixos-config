{
  lib,
  config,
  pkgs,
  ...
}: let
  inherit (lib.lists) unique;
in {
  options.nix.mpvOpenvr.enable = lib.mkEnableOption "Build mpv with experimental OpenVR overlay support (may fail).";

  config = lib.mkIf config.nix.mpvOpenvr.enable {
    nixpkgs.overlays = [
      (final: prev: let
        extraInputs = unique [
          prev.openvr
          prev.xorg.libX11
          prev.xorg.libXext
          prev.xorg.libXinerama
          prev.xorg.libXi
          prev.libGL
        ];
      in {
        mpv = prev.mpv.overrideAttrs (old: {
          patches = (old.patches or []) ++ [./patches/mpv-openvr.patch];
          buildInputs = unique ((old.buildInputs or []) ++ extraInputs);
          nativeBuildInputs = unique ((old.nativeBuildInputs or []) ++ [prev.pkg-config]);
          # Note: upstream mpv does not expose an 'openvr' meson option; this overlay is experimental.
        });
      })
    ];
  };
}
