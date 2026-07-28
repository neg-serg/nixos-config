{ ... }:
{
  imports = [
    ./session
    ./nix-maid
    ./games
    ./dbus.nix
    ./fonts.nix
    ./gui-packages.nix
    ./locale.nix
    ./locale-pkgs.nix # Nix package manager
    ./locate.nix
    ./mail.nix
    ./neovim.nix
    ./theme-packages.nix
    ./xdg.nix
  ];
}
