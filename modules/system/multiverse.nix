# nixpkgs-multiverse: pin any top-level nixpkgs attribute (pkgs.*) to an exact
# version from a single flake input — no juggling multiple nixpkgs pins.
# No pins configured yet; add e.g.:
#   multiverse.pins.ripgrep = "13.0.0";
# Pinned derivations are also available as config.multiverse.pinned.<attr>.
{
  inputs,
  ...
}:
{
  imports = [ inputs.multiverse.nixosModules.default ];
  multiverse.enable = true;
}
