_: {
  nixpkgs.overlays = [
    (import ../../packages/overlay.nix)
  ];
}
