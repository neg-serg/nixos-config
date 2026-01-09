{
  # Shared binary caches and public keys for both flake.nix (nixConfig)
  # and modules/nix/settings.nix (nix.settings).
  # Only official NixOS cache - third-party caches disabled for reliability.
  substituters = [
    "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
    "https://cache.nixos.kz"
    "https://nixos-cache-proxy.cofob.dev"
    "https://nixos-cache-proxy.sweetdogs.ru"
    "https://ncproxy.vizqq.cc"
    "https://cache.nixos.org/"
  ];

  trusted-public-keys = [
    # Official NixOS cache
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  ];
}
