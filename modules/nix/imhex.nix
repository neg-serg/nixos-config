{ ... }:
{
  nixpkgs.overlays = [
    (_: prev: {
      imhex = prev.imhex.overrideAttrs (old: {
        # Raise embedded edlib's CMake minimum version to satisfy >=3.5 policy.
        patches = (old.patches or []) ++ [
          ./patches/imhex-edlib-min-cmake-3_5.patch
        ];
        # Make the build treat deprecated declarations as warnings rather than errors.
        NIX_CFLAGS_COMPILE =
          ((old.NIX_CFLAGS_COMPILE or "")
            + " -Wno-error=deprecated-declarations");
      });
    })
  ];
}
