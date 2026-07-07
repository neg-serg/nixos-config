{ inputs, ... }:
{
  nixpkgs.overlays = [
    (import (inputs.self + "/packages/overlay.nix") inputs)
    # Enable ccache for all local Nix builds (compiled through stdenv).
    # Wraps gcc/clang so object files are cached in /cache.
    (final: prev: {
      stdenv = prev.ccacheStdenv;
    })
  ];
}
