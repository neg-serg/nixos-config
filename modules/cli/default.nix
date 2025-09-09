{...}: {
  imports = [
    ./tmux
    ./archives
    ./ugrep.nix
    ./pkgs.nix
  ];
  # Packages are in ./pkgs.nix
}
