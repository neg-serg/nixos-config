{lib, ...}: let
  inherit (lib.lists) unique;
in {
  nixpkgs.overlays = [
    (final: prev: let
      extraInputs = unique ([
        prev.openvr
        prev.libX11
        prev.libXext
        prev.libXinerama
        prev.libXi
        prev.libGL
      ]);
    in {
      mpv = prev.mpv.overrideAttrs (old: {
        patches = (old.patches or []) ++ [./patches/mpv-openvr.patch];
        buildInputs = unique ((old.buildInputs or []) ++ extraInputs);
        nativeBuildInputs = unique ((old.nativeBuildInputs or []) ++ [prev.pkg-config]);
        mesonFlags = (old.mesonFlags or []) ++ ["-Dopenvr=enabled"];
      });
    })
  ];
}
