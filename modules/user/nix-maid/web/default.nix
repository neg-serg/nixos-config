# defaults.nix / browsers-table.nix / surfingkeys-server.nix are helpers
# imported by browsing.nix — not standalone modules.
{
  imports = [
    ./aria.nix
    ./browsing.nix
    ./vivaldi.nix
    ./yt-dlp.nix
  ];
}
