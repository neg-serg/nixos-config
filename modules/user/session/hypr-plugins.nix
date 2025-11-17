{pkgs, ...}: {
  # Provide a stable, GC-resistant path for the hy3 plugin.
  # This avoids hardcoding Nix store hashes in user config and prevents
  # ABI mismatches by sourcing the plugin from the current nixpkgs.
  environment.etc."hypr/libhy3.so".source = "${pkgs.hyprlandPlugins.hy3}/lib/libhy3.so";
}
