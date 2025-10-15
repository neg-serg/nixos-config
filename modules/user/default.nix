{...}: {
  imports = [
    ./bash.nix
    ./dbus.nix
    ./fonts.nix
    ./games
    ./locale.nix
    ./locale-pkgs.nix
    ./locate.nix
    ./psd # profile sync daemon
    ./session
    ./session/plasma-uwsm.nix
    ./session/hypr-bindings.nix
    ./session/pkgs.nix
    ./xdg.nix
  ];
}
