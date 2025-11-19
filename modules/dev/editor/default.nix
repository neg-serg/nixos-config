{...}: {
  programs.nano = {enable = false;};
  imports = [
    ./pkgs.nix
    ./neovim/pkgs.nix
  ];
}
