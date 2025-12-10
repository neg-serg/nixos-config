{
  pkgs,
  inputs,
  ...
}: let
  spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.system};
in {
  # Import the spicetify module from the flake
  imports = [inputs.spicetify-nix.homeManagerModules.default];

  programs.spicetify = {
    enable = true;

    # Use the Catppuccin text theme to match system
    # Assuming 'catppuccin' is available in themes
    theme = spicePkgs.themes.catppuccin;
    colorScheme = "mocha";

    enabledExtensions = with spicePkgs.extensions; [
      adblock
      shuffle # shuffling improvements
      fullAppDisplay
    ];
  };
}
