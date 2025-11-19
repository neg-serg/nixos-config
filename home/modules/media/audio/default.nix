{lib, ...}:
with lib; {
  imports = [
    ./beets.nix
    ./ncpamixer.nix
    ./rmpc.nix
    ./mpd
  ];
}
