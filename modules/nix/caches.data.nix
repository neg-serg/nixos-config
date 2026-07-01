{
  # Shared binary caches and public keys for both flake.nix (nixConfig)
  # and modules/nix/settings.nix (nix.settings).
  # Local nginx cache proxy (127.0.0.1:3210) backed by cache.nixos.org,
  # followed by the official cache and community mirrors.
  substituters = [
    "http://127.0.0.1:3210"
    "https://cache.nixos.org/"
    "https://nix-community.cachix.org"
    "https://install.determinate.systems"
  ];

  trusted-public-keys = [
    # Official NixOS cache
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    # nix-community public cache
    "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    # Determinate Systems / FlakeHub
    "install.determinate.systems:2/bvnFWPrR6uxEXpB7XqOSykYemH8e8WoMWvoLLXpF4="
    "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
  ];
}
