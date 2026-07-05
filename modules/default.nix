# Dendritic module entry point — each domain composes its own submodules.
# Replaces the flat-import pattern previously in flat.nix.
{
  imports = [
    ./appimage/default.nix
    ./apps/default.nix
    ./cli/default.nix
    ./core/default.nix
    ./dev/default.nix
    ./diff-closures.nix
    ./documentation/default.nix
    ./emulators/default.nix
    ./features/default.nix
    ./flake-preflight.nix
    ./fonts/default.nix
    ./fun/default.nix
    ./games/default.nix
    ./hardware/default.nix
    ./llm/default.nix
    ./media/default.nix
    ./monitoring/default.nix
    ./nix/default.nix
    ./profiles/default.nix
    ./roles/default.nix
    ./secrets/default.nix
    ./security/default.nix
    ./servers/default.nix
    ./shell/default.nix
    ./system/default.nix
    ./text/default.nix
    ./tools/default.nix
    ./torrent/default.nix
    ./user/default.nix
    ./web/default.nix
  ];
}
