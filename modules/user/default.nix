{...}: {
  imports = [
    ./bash.nix
    ./dbus.nix
    ./fonts.nix
    ./games
    ./mail.nix
    ./locale.nix
    ./locale-pkgs.nix
    ./locate.nix
    ./psd # profile sync daemon
    ./session
    ./session/hypr-bindings.nix
    ./session/pkgs.nix
    ./xdg.nix
  ];
}
