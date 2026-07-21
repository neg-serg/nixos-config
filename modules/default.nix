# Dendritic module entry point — each domain composes its own submodules.
#
# Architecture (parallel-eval refactoring, Jul 2026):
#   domainFilter :: string -> bool  (passed via specialArgs)
#   Controls which domain modules are imported. Default imports all.
#   Each host/test config can pass a restrictive filter to skip unused
#   domains, reducing the evaluation tree and enabling more parallel
#   evaluation via nix-eval-jobs.
#
#   Example: a headless server passes `domainFilter = n: n != "user" && n != "games"`
#   and skips Hyprland, nix-maid, gaming modules (~90 files fewer to import).
{
  lib,
  domainFilter ? (_: true),
  ...
}:
let
  # `domain`: if filter(name) passes, include one module path; otherwise nothing.
  domain = name: elem: lib.optional (domainFilter name) elem;
in
{
  imports =
    domain "appimage" ./appimage/default.nix
    ++ domain "apps" ./apps/default.nix
    ++ domain "cli" ./cli/default.nix
    ++ domain "core" ./core/default.nix
    ++ domain "dev" ./dev/default.nix
    ++ domain "diff-closures" ./diff-closures.nix
    ++ domain "documentation" ./documentation/default.nix
    ++ domain "emulators" ./emulators/default.nix
    ++ domain "features" ./features/default.nix
    ++ domain "flatpak" ./flatpak/default.nix
    ++ domain "flake-preflight" ./flake-preflight.nix
    ++ domain "fonts" ./fonts/default.nix
    ++ domain "fun" ./fun/default.nix
    ++ domain "games" ./games/default.nix
    ++ domain "hardware" ./hardware/default.nix
    ++ domain "llm" ./llm/default.nix
    ++ domain "media" ./media/default.nix
    ++ domain "monitoring" ./monitoring/default.nix
    ++ domain "nix" ./nix/default.nix
    ++ domain "profiles" ./profiles/default.nix
    ++ domain "roles" ./roles/default.nix
    ++ domain "secrets" ./secrets/default.nix
    ++ domain "security" ./security/default.nix
    ++ domain "servers" ./servers/default.nix
    ++ domain "shell" ./shell/default.nix
    ++ domain "system" ./system/default.nix
    ++ domain "text" ./text/default.nix
    ++ domain "tools" ./tools/default.nix
    ++ domain "torrent" ./torrent/default.nix
    ++ domain "user" ./user/default.nix
}
