_: {
  nixpkgs.overlays = [
    (_: prev: {
      clblast = prev.clblast.overrideAttrs (old: {
        # Bump CLBlast's CMake floor to match current CMake policy requirements.
        patches =
          (old.patches or [])
          ++ [
            ./patches/clblast-min-cmake-3_5.patch
          ];
      });
    })
  ];
}
