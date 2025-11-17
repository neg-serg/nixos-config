_: {
  nixpkgs.overlays = [
    (import ../../home/packages/overlay.nix)
  ];
}
