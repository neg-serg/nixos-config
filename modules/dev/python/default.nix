{ ... }:
{
  # nixpkgs.config.packageOverrides moved to packages/overlay.nix
  # python3-lto defined there as well
  imports = [ ./pkgs.nix ]; # Nix package manager
}
