{lib, ...}:
with lib; {
  imports = [
    ./beets.nix
    ./ncpamixer.nix
    ./rmpc.nix
    ./subsonic.nix
    ./mpd
  ];
}
