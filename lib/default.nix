{ lib }:
{
  # Option helpers to reduce boilerplate in modules
  opts = import ./opts.nix { inherit lib; };
}

