{ ... }:
{
  imports = [
    ./session
    ./nix-maid
    ./games
    ./bash.nix
    ./dbus.nix
    ./fonts.nix
    ./gui-packages.nix
    ./locale.nix
    ./locale-pkgs.nix # Nix package manager
    ./locate.nix
    ./mail.nix
    ./neovim.nix
    ./psd
    ./theme-packages.nix
    ./xdg.nix
    ./wrappers
  ];
}
