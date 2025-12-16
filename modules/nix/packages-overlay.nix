{inputs, ...}: {
  nixpkgs.overlays = [
    (import (inputs.self + "/packages/overlay.nix") inputs)
  ];
}
