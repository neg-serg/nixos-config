{lib, config, ...}:
with lib; {
  imports = [
    ./neovim
    ./helix
  ];
  # Editor packages (code-cursor, LM Studio) now install via modules/dev/editor/pkgs.nix.
  config = lib.mkMerge [
    (mkIf (config.features.dev.ai.enable or false) {
      programs.claude-code.enable = true;
    })
  ];
}
