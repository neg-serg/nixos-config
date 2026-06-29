{
  # Shared binary caches and public keys for both flake.nix (nixConfig)
  # and modules/nix/settings.nix (nix.settings).
  # Official NixOS cache + Russian mirrors for lower latency.
  substituters = [
    "https://ncproxy.vizqq.cc"
    "https://cache.nixos.org/"
  ];

  trusted-public-keys = [
    # Official NixOS cache
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    # Determinate Systems
    "install.determinate.systems:2/bvnFWPrR6uxEXpB7XqOSykYemH8e8WoMWvoLLXpF4="
  ];
}
