{lib, config, ...}:
lib.mkIf config.features.dev.enable {
  # Neovim LSP/tooling packages now handled via modules/dev/editor/neovim/pkgs.nix.
}
