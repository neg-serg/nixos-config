{ neg, ... }:
{
  # Data directories here are not modules (the dsh-* asset/preset bundles and
  # dsh-tui-assets/); importDir skips directories without a default.nix.
  # A plain data file needs an explicit exclusion: dsh-terminal-plugins.nix is
  # the plugin roster and dsh-presets.nix the agent-preset declarations (both
  # imported by the tui-profile module, neither is a NixOS module).
  imports = neg.importDir {
    dir = ./.;
    includeDirs = true;
    exclude = [
      "dsh-terminal-plugins.nix"
      "dsh-presets.nix"
    ];
  };
}
