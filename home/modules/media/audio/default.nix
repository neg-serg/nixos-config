{lib, ...}:
with lib; {
  imports = [
    ./beets.nix

    ./rmpc.nix
    ./subsonic.nix
    # ./mpd.nix
    # ./mpdris2.nix
  ];
}
