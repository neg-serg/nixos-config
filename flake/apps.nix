{
  self,
  ...
}:
system: {
  apps = {
    # Same treefmt wrapper as the flake `formatter` output — single source of
    # truth (per-system.nix), so `nix run .#fmt` and `nix fmt` stay in sync.
    fmt = {
      type = "app";
      program = "${self.formatter.${system}}/bin/fmt";
    };
  };
}
