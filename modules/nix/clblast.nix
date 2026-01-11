_: {
  nixpkgs.overlays = [
    (_: prev: {
      clblast = prev.clblast.overrideAttrs (old: {
        patches = old.patches or [ ];
      });
    })
  ];
}
