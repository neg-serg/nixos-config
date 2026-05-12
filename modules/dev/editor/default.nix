{ ... }:
{
  programs.nano = {
    enable = false;
  };
  imports = [
    ./pkgs.nix # Nix package manager
    ./neovim/pkgs.nix # Nix package manager
  ];
}
