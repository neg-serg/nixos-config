{
  # Shared binary caches and public keys for both flake.nix (nixConfig)
  # and modules/nix/settings.nix (nix.settings).
  # Official NixOS cache + Russian mirrors for lower latency.
  substituters = [
    "https://ncproxy.vizqq.cc"
    "https://nix-community.cachix.org"
    "https://cache.nixos.org/"
  ];

  trusted-public-keys = [
    # Official NixOS cache
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    # nix-community public cache
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    # Determinate Systems (unused, kept for reference)
    "install.determinate.systems:2/bvnFWPrR6uxEXpB7XqOSykYemH8e8WoMWvoLLXpF4="
  ];
}
